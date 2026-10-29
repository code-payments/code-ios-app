//
//  PathAwareDNSResolver.swift
//  FlipcashCore
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Network
import Synchronization

private let logger = Logger(label: "flipcash.grpc-resolver")

/// A DNS target whose addresses are looked up again every time the network path changes.
struct PathAwareDNSTarget: ResolvableTarget, Sendable {
    /// The host name to resolve.
    var host: String
    /// The port every resolved address connects to.
    var port: Int
}

/// Makes resolvers that push a fresh address list to the channel whenever the network path changes.
// grpc-swift's `.dns` resolver only looks up again after an established connection drops or
// on GOAWAY, so a failed dial retries stale addresses forever: IPv4-only Wi-Fi to IPv6-only
// cellular left every RPC dialing an unreachable IPv4 address until relaunch.
struct PathAwareDNSResolverFactory: NameResolverFactory, Sendable {
    typealias Target = PathAwareDNSTarget

    /// Emits once per relevant network path change, after the initial path.
    var pathChanges: @Sendable () -> AsyncStream<Void> = NetworkPathChanges.stream

    /// Looks up the socket addresses for a host and port.
    var lookup: @Sendable (_ host: String, _ port: Int) async throws -> [SocketAddress] = AddressLookup.resolve

    /// Waits before each repeat lookup when a path change returns the previous addresses.
    var settleDelays: [Duration] = [.seconds(1), .seconds(3)]

    /// Suspends for the given duration.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func resolver(for target: PathAwareDNSTarget) -> NameResolver {
        let sequence = Sequence(
            target: target,
            pathChanges: pathChanges,
            lookup: lookup,
            settleDelays: settleDelays,
            sleep: sleep
        )
        return NameResolver(
            names: RPCAsyncSequence(wrapping: sequence),
            updateMode: .push,
            authority: "\(target.host):\(target.port)"
        )
    }

    /// Resolution results for one target: one immediately, then one per path change.
    // The channel makes a new iterator after every error, so a failed lookup is retried
    // after its backoff rather than waiting for the next path change.
    struct Sequence: AsyncSequence, Sendable {
        typealias Element = NameResolutionResult

        /// The host and port being resolved.
        let target: PathAwareDNSTarget
        /// Source of path-change ticks, one stream per iterator.
        let pathChanges: @Sendable () -> AsyncStream<Void>
        /// Looks up the socket addresses for a host and port.
        let lookup: @Sendable (String, Int) async throws -> [SocketAddress]
        /// Waits before each repeat lookup when a path change returns the previous addresses.
        let settleDelays: [Duration]
        /// Suspends for the given duration.
        let sleep: @Sendable (Duration) async throws -> Void

        func makeAsyncIterator() -> Iterator {
            Iterator(sequence: self, changes: pathChanges().makeAsyncIterator())
        }

        /// Yields the first result immediately and each later one after a path change.
        struct Iterator: AsyncIteratorProtocol {
            /// The sequence this iterator resolves for.
            let sequence: Sequence
            /// Path-change ticks that gate every result after the first.
            var changes: AsyncStream<Void>.Iterator
            /// The addresses last returned, or `nil` before the first result.
            var lastAddresses: [SocketAddress]?

            /// Returns the next resolution result, throwing `CancellationError` once the path stream ends.
            mutating func next() async throws -> NameResolutionResult? {
                guard let previous = lastAddresses else {
                    return try await resolve()
                }

                // A finished stream means the task was cancelled; returning nil would
                // make the channel back off and resolve again instead of stopping.
                guard await changes.next() != nil else { throw CancellationError() }
                logger.info("Network path changed, resolving again", metadata: ["host": "\(sequence.target.host)"])

                // The channel ignores an unchanged address list, and DNS can answer from the
                // old path for a moment after the switch, so look again before giving up.
                var result = try await resolve()
                for delay in sequence.settleDelays where lastAddresses == previous {
                    try await sequence.sleep(delay)
                    result = try await resolve()
                }
                return result
            }

            private mutating func resolve() async throws -> NameResolutionResult {
                try Task.checkCancellation()
                let addresses = try await sequence.lookup(sequence.target.host, sequence.target.port)
                lastAddresses = addresses
                return NameResolutionResult(endpoints: [Endpoint(addresses: addresses)], serviceConfig: nil)
            }
        }
    }
}

/// Network path changes that can alter which addresses `getaddrinfo` returns.
enum NetworkPathChanges {

    private struct Key: Equatable {
        var status: NWPath.Status
        var supportsIPv4: Bool
        var supportsIPv6: Bool
        var interfaces: [NWInterface.InterfaceType]

        init(_ path: NWPath) {
            status = path.status
            supportsIPv4 = path.supportsIPv4
            supportsIPv6 = path.supportsIPv6
            interfaces = path.availableInterfaces.map(\.type)
        }
    }

    /// A stream backed by its own `NWPathMonitor` that skips the initial path and repeats.
    static func stream() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            let last = Mutex<Key?>(nil)
            monitor.pathUpdateHandler = { path in
                let key = Key(path)
                let changed = last.withLock { last in
                    defer { last = key }
                    return last != nil && last != key
                }
                if changed {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "flipcash.grpc-resolver.path"))
        }
    }
}

/// `getaddrinfo` lookups for TCP connections.
enum AddressLookup {

    /// A `getaddrinfo` failure.
    struct Failure: Error {
        /// The `EAI_*` code `getaddrinfo` returned.
        let code: Int32
    }

    private static let queue = DispatchQueue(label: "flipcash.grpc-resolver.lookup")

    /// Resolves `host` to the addresses the current network path can reach.
    static func resolve(host: String, port: Int) async throws -> [SocketAddress] {
        // AI_DEFAULT (AI_V4MAPPED_CFG | AI_ADDRCONFIG) returns only families the current
        // path can reach and synthesizes NAT64 addresses on IPv6-only networks.
        try await resolve(host: host, port: port, flags: AI_DEFAULT)
    }

    /// Resolves `host` with the given `getaddrinfo` flags, off the caller's thread.
    static func resolve(host: String, port: Int, flags: Int32) async throws -> [SocketAddress] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try resolveBlocking(host: host, port: port, flags: flags) })
            }
        }
    }

    private static func resolveBlocking(host: String, port: Int, flags: Int32) throws -> [SocketAddress] {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        hints.ai_flags = flags

        var result: UnsafeMutablePointer<addrinfo>?
        let code = getaddrinfo(host, String(port), &hints, &result)
        guard code == 0, let first = result else { throw Failure(code: code) }
        defer { freeaddrinfo(first) }

        var addresses: [SocketAddress] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let info = node {
            node = info.pointee.ai_next
            guard let address = info.pointee.ai_addr,
                  let numericHost = numericHost(address, length: info.pointee.ai_addrlen)
            else { continue }

            switch Int32(info.pointee.ai_family) {
            case AF_INET:
                addresses.append(.ipv4(host: numericHost, port: port))
            case AF_INET6:
                addresses.append(.ipv6(host: numericHost, port: port))
            default:
                continue
            }
        }
        return addresses
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>, length: socklen_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }
}
