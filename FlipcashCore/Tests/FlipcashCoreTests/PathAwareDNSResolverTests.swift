//
//  PathAwareDNSResolverTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import Synchronization
import GRPCNIOTransportHTTP2
@testable import FlipcashCore

@Suite("PathAwareDNSResolver")
struct PathAwareDNSResolverTests {

    private static let ipv4: SocketAddress = .ipv4(host: "3.95.74.41", port: 443)
    private static let nat64: SocketAddress = .ipv6(host: "64:ff9b::35f:4a29", port: 443)
    private static let target = PathAwareDNSTarget(host: "api.example.com", port: 443)

    private struct LookupFailed: Error {}

    @Test("Resolves again with the new path's addresses after a path change")
    func resolvesAgainOnPathChange() async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let answers = Mutex([[Self.ipv4], [Self.nat64]])
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { changes },
            lookup: { _, _ in answers.withLock { $0.removeFirst() } }
        )

        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()

        let first = try await iterator.next()
        #expect(first?.endpoints == [Endpoint(addresses: [Self.ipv4])])

        continuation.yield()
        let second = try await iterator.next()
        #expect(second?.endpoints == [Endpoint(addresses: [Self.nat64])])
    }

    @Test("A new iterator after a failed lookup resolves without waiting for a path change")
    func newIteratorResolvesImmediately() async throws {
        let calls = Mutex(0)
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { AsyncStream { _ in } },
            lookup: { _, _ in
                let call = calls.withLock { $0 += 1; return $0 }
                if call == 1 { throw LookupFailed() }
                return [Self.ipv4]
            }
        )
        let names = factory.resolver(for: Self.target).names

        var failing = names.makeAsyncIterator()
        await #expect(throws: LookupFailed.self) { try await failing.next() }

        var retry = names.makeAsyncIterator()
        let result = try await retry.next()
        #expect(result?.endpoints == [Endpoint(addresses: [Self.ipv4])])
    }

    @Test("Resolves again once, without settle delays, on a resolve request")
    func resolvesAgainOnRequest() async throws {
        let (requests, continuation) = AsyncStream<Void>.makeStream()
        let lookups = Mutex(0)
        let sleeps = Mutex<[Duration]>([])
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { AsyncStream { _ in } },
            resolveRequests: { requests },
            lookup: { _, _ in lookups.withLock { $0 += 1 }; return [Self.ipv4] },
            sleep: { duration in sleeps.withLock { $0.append(duration) } }
        )
        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()
        _ = try await iterator.next()

        continuation.yield()
        let result = try await iterator.next()

        #expect(result?.endpoints == [Endpoint(addresses: [Self.ipv4])])
        #expect(lookups.withLock { $0 } == 2)
        #expect(sleeps.withLock { $0 }.isEmpty)
    }

    @Test("Ending the request stream leaves path changes working")
    func finishedRequestStreamKeepsPathChanges() async throws {
        let (changes, changesContinuation) = AsyncStream<Void>.makeStream()
        let answers = Mutex([[Self.ipv4], [Self.nat64]])
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { changes },
            resolveRequests: { AsyncStream { $0.finish() } },
            lookup: { _, _ in answers.withLock { $0.removeFirst() } }
        )
        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()
        _ = try await iterator.next()

        changesContinuation.yield()
        let result = try await iterator.next()
        #expect(result?.endpoints == [Endpoint(addresses: [Self.nat64])])
    }

    @Test("Ending the path stream throws cancellation instead of returning nil")
    func finishedPathStreamThrowsCancellation() async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { changes },
            lookup: { _, _ in [Self.ipv4] }
        )
        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()
        _ = try await iterator.next()

        continuation.finish()
        await #expect(throws: CancellationError.self) { try await iterator.next() }
    }

    @Test("Resolver pushes updates and keeps the host:port authority")
    func resolverShape() {
        let resolver = PathAwareDNSResolverFactory().resolver(for: Self.target)
        #expect(resolver.updateMode == .push)
        #expect(resolver.authority == "api.example.com:443")
    }

    @Test("The app transport finds a resolver for its target")
    func transportBuildsWithResolver() throws {
        _ = try GRPCTransport.makeClient(host: "api.example.com", port: 443)
    }

    @Test("Looks again while a path change keeps returning the old addresses")
    func retriesUnchangedAddresses() async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let answers = Mutex([[Self.ipv4], [Self.ipv4], [Self.nat64]])
        let sleeps = Mutex<[Duration]>([])
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { changes },
            lookup: { _, _ in answers.withLock { $0.removeFirst() } },
            settleDelays: [.seconds(1), .seconds(3)],
            sleep: { duration in sleeps.withLock { $0.append(duration) } }
        )
        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()
        _ = try await iterator.next()

        continuation.yield()
        let result = try await iterator.next()

        #expect(result?.endpoints == [Endpoint(addresses: [Self.nat64])])
        #expect(sleeps.withLock { $0 } == [.seconds(1)])
    }

    @Test("Returns the old addresses once every settle delay has passed")
    func givesUpAfterSettleDelays() async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        let lookups = Mutex(0)
        let factory = PathAwareDNSResolverFactory(
            pathChanges: { changes },
            lookup: { _, _ in lookups.withLock { $0 += 1 }; return [Self.ipv4] },
            settleDelays: [.seconds(1), .seconds(3)],
            sleep: { _ in }
        )
        var iterator = factory.resolver(for: Self.target).names.makeAsyncIterator()
        _ = try await iterator.next()

        continuation.yield()
        let result = try await iterator.next()

        #expect(result?.endpoints == [Endpoint(addresses: [Self.ipv4])])
        #expect(lookups.withLock { $0 } == 4)
    }

    @Test("getaddrinfo lookup maps a numeric host to a socket address")
    func lookupNumericHost() async throws {
        // AI_NUMERICHOST alone skips AI_ADDRCONFIG, so the result doesn't depend on the host's interfaces.
        let addresses = try await AddressLookup.resolve(host: "127.0.0.1", port: 443, flags: AI_NUMERICHOST)
        #expect(addresses == [.ipv4(host: "127.0.0.1", port: 443)])
    }
}
