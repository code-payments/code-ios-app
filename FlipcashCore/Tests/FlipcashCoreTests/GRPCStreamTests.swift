//
//  GRPCStreamTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
import Synchronization
@testable import FlipcashCore

@Suite("GRPCStream adapters — retained handles over gRPC v2 closure-scoped streaming")
struct GRPCStreamTests {

    private struct TestError: Error {}

    // MARK: - BidirectionalGRPCStream -

    @Test("Outbound messages buffer before open and drain in order")
    func bidiBuffersAndDrainsOutboundMessages() async {
        let stream = BidirectionalGRPCStream<Int, Never>()
        stream.sendMessage(1)

        let (collected, continuation) = AsyncStream.makeStream(of: [Int].self)
        stream.open(onResponse: { _ in }) { requests, _ in
            var values: [Int] = []
            for await value in requests {
                values.append(value)
                if values.count == 3 { break }
            }
            continuation.yield(values)
        }
        stream.sendMessage(2)
        stream.sendMessage(3)

        let values = await collected.first { _ in true }
        #expect(values == [1, 2, 3])
    }

    @Test("onComplete fires exactly once with the thrown error")
    func bidiOnCompleteFiresOnceWithThrownError() async {
        let stream = BidirectionalGRPCStream<Int, Never>()
        let (results, continuation) = AsyncStream.makeStream(of: Result<Void, any Error>.self)
        let fireCount = Mutex(0)

        stream.open(onResponse: { _ in }, onComplete: { result in
            fireCount.withLock { $0 += 1 }
            continuation.yield(result)
        }) { _, _ in
            throw TestError()
        }

        let result = await results.first { _ in true }
        guard case .failure(let error) = result else {
            Issue.record("Expected a failure result")
            return
        }
        #expect(error is TestError)
        #expect(fireCount.withLock { $0 } == 1)
    }

    @Test("Explicit cancel suppresses onComplete — user teardown is not a stream error")
    func bidiCancelSuppressesOnComplete() async throws {
        let stream = BidirectionalGRPCStream<Int, Never>()
        let fired = Mutex(false)

        stream.open(onResponse: { _ in }, onComplete: { _ in
            fired.withLock { $0 = true }
        }) { _, _ in
            try await Task.sleep(for: .seconds(60))
        }
        stream.cancel()

        try await Task.sleep(for: .milliseconds(200))
        #expect(fired.withLock { $0 } == false)
    }

    // MARK: - ServerGRPCStream -

    @Test("Re-opening after completion works — the messaging re-subscribe chain survives repeated closes")
    func serverStreamSupportsReopenAfterCompletion() async {
        let stream = ServerGRPCStream()
        let (completions, continuation) = AsyncStream.makeStream(of: Int.self)
        let count = Mutex(0)

        @Sendable func subscribe() {
            stream.open(onComplete: { _ in
                let n = count.withLock { value -> Int in
                    value += 1
                    return value
                }
                if n < 3 { subscribe() }
                continuation.yield(n)
            }) {
                // Returning immediately models the server closing the stream.
            }
        }
        subscribe()

        var last = 0
        for await n in completions {
            last = n
            if n == 3 { break }
        }
        #expect(last == 3)
    }

    @Test("Cancel is sticky — open after cancel never starts the RPC")
    func serverStreamCancelIsSticky() async throws {
        let stream = ServerGRPCStream()
        stream.cancel()

        let performed = Mutex(false)
        stream.open(onComplete: { _ in }) {
            performed.withLock { $0 = true }
        }

        try await Task.sleep(for: .milliseconds(200))
        #expect(performed.withLock { $0 } == false)
    }

    @Test("Re-open supersedes an in-flight connection — the stale completion never fires")
    func serverStreamReopenSupersedesInFlight() async throws {
        let stream = ServerGRPCStream()
        let (started, startedContinuation) = AsyncStream.makeStream(of: Void.self)
        let completions = Mutex<[String]>([])

        stream.open(onComplete: { _ in
            completions.withLock { $0.append("first") }
        }) {
            startedContinuation.yield(())
            try await Task.sleep(for: .seconds(60))
        }
        _ = await started.first { _ in true }

        let (done, doneContinuation) = AsyncStream.makeStream(of: Void.self)
        stream.open(onComplete: { _ in
            completions.withLock { $0.append("second") }
            doneContinuation.yield(())
        }) {
            // Returns immediately — supersedes the sleeping first connection.
        }
        _ = await done.first { _ in true }

        // Give the superseded (cancelled) first task time to run its finish path,
        // which the generation guard must suppress.
        try await Task.sleep(for: .milliseconds(200))
        #expect(completions.withLock { $0 } == ["second"])
    }

    @Test("Server stream cancel suppresses onComplete")
    func serverStreamCancelSuppressesOnComplete() async throws {
        let stream = ServerGRPCStream()
        let fired = Mutex(false)

        stream.open(onComplete: { _ in
            fired.withLock { $0 = true }
        }) {
            try await Task.sleep(for: .seconds(60))
        }
        stream.cancel()

        try await Task.sleep(for: .milliseconds(200))
        #expect(fired.withLock { $0 } == false)
    }
}
