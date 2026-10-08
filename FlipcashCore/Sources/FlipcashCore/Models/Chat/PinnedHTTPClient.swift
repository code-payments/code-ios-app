//
//  PinnedHTTPClient.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Network

/// The URL is not one a link preview may fetch.
public nonisolated struct NotAllowed: Error, Equatable, Sendable {
    public init() {}
}

/// Every address the host resolved to is private, local or otherwise not public.
public nonisolated struct NoPublicAddress: Error, Equatable, Sendable {
    public let host: String
    public init(host: String) { self.host = host }
}

/// The connection ended before a response arrived or did not become ready in time.
public nonisolated struct PinnedConnectionFailed: Error, Equatable, Sendable {
    public init() {}
}

/// Resolves a host and keeps the first address the fixture's rule calls public.
public nonisolated struct PublicAddressResolver: Sendable {
    public var lookup: @Sendable (String) async throws -> [any IPAddress]

    public init(lookup: @escaping @Sendable (String) async throws -> [any IPAddress] = PublicAddressResolver.system) {
        self.lookup = lookup
    }

    public func resolve(_ host: String) async throws -> any IPAddress {
        guard let address = try await lookup(host).first(where: { WebLinks.isPublic($0) }) else {
            throw NoPublicAddress(host: host)
        }
        return address
    }

    /// `getaddrinfo` for both families, run off the caller's thread.
    @Sendable public static func system(_ host: String) async throws -> [any IPAddress] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var head: UnsafeMutablePointer<addrinfo>?
                let code = getaddrinfo(host, nil, &hints, &head)
                guard code == 0 else {
                    continuation.resume(throwing: URLError(.cannotFindHost))
                    return
                }
                defer { freeaddrinfo(head) }
                var found: [any IPAddress] = []
                var node = head
                while let info = node?.pointee {
                    if info.ai_family == AF_INET, let sa = info.ai_addr {
                        let raw = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                        if let a = IPv4Address(withUnsafeBytes(of: raw) { Data($0) }) { found.append(a) }
                    } else if info.ai_family == AF_INET6, let sa = info.ai_addr {
                        let raw = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                        if let a = IPv6Address(withUnsafeBytes(of: raw) { Data($0) }) { found.append(a) }
                    }
                    node = info.ai_next
                }
                continuation.resume(returning: found)
            }
        }
    }
}

public protocol PinnedFetching: Sendable {
    /// One GET, no redirects followed.
    func get(_ url: URL, accept: String, maxBytes: Int) async throws -> PinnedResponse
}

/// One HTTP/1.1 GET over a connection to an address that was already checked.
/// URLSession resolves again on its own, so it cannot promise where it connects; this can.
public nonisolated struct PinnedHTTPClient: PinnedFetching {

    public var resolver: PublicAddressResolver

    public init(resolver: PublicAddressResolver = PublicAddressResolver()) {
        self.resolver = resolver
    }

    public func get(_ url: URL, accept: String, maxBytes: Int) async throws -> PinnedResponse {
        guard url.scheme?.lowercased() == "https", let host = Self.asciiHost(url) else { throw NotAllowed() }
        let address = try await resolver.resolve(host)

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(WebLinks.timeout)
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.preferNoProxies = true

        let endpointHost: NWEndpoint.Host
        if let v6 = address as? IPv6Address { endpointHost = .ipv6(v6) }
        else if let v4 = address as? IPv4Address { endpointHost = .ipv4(v4) }
        else { throw NotAllowed() }
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: url.port ?? 443)) else { throw NotAllowed() }

        let connection = NWConnection(host: endpointHost, port: port, using: parameters)
        let request = Self.requestBytes(for: url, accept: accept)

        return try await withTaskCancellationHandler {
            defer { connection.cancel() }
            return try await withThrowingTaskGroup(of: PinnedResponse.self) { group in
                group.addTask {
                    try await Self.awaitReady(connection)
                    try await Self.send(request, on: connection)
                    var reader = HTTP1ResponseReader(maxBytes: maxBytes)
                    while true {
                        let (data, isComplete) = try await Self.receive(on: connection)
                        if let data, !data.isEmpty, case .done(let response) = try reader.feed(data) {
                            return response
                        }
                        if isComplete { return try reader.finish() }
                    }
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(2 * WebLinks.timeout))
                    connection.cancel()   // unblocks the fetch child, which a continuation would hold forever
                    throw URLError(.timedOut)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// The exact bytes of the request: no cookies, no credentials, no compression.
    public static func requestBytes(for url: URL, accept: String) -> Data {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var target = components?.percentEncodedPath ?? ""
        if target.isEmpty { target = "/" }
        if let query = components?.percentEncodedQuery { target += "?" + query }
        let host = asciiHost(url) ?? ""
        let hostHeader = (url.port ?? 443) == 443 ? host : "\(host):\(url.port ?? 443)"
        let text = "GET \(target) HTTP/1.1\r\n"
            + "Host: \(hostHeader)\r\n"
            + "User-Agent: \(WebLinks.userAgent)\r\n"
            + "Accept: \(accept)\r\n"
            + "Accept-Encoding: identity\r\n"
            + "Connection: close\r\n\r\n"
        return Data(text.utf8)
    }

    /// The lowercased punycode host, or nil when there is no usable one.
    static func asciiHost(_ url: URL) -> String? {
        WebLinks.host(of: url)
    }

    // MARK: - NWConnection as async -

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func claim() -> Bool { lock.withLock { defer { fired = true }; return !fired } }
    }

    private static func awaitReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                case .waiting(let error):
                    // Waiting means no route or a failed handshake that would retry forever.
                    if once.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private static func receive(on connection: NWConnection) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (data, isComplete)) }
            }
        }
    }
}
