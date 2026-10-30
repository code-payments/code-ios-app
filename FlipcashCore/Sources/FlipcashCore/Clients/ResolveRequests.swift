//
//  ResolveRequests.swift
//  FlipcashCore
//

import Foundation
import Synchronization

/// Fans a request to resolve the server again out to every live resolver of one client, at most once per interval.
final class ResolveRequests: Sendable {

    private struct State {
        var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]
        var lastSent: ContinuousClock.Instant?
    }

    private let state = Mutex(State())
    private let minimumInterval: Duration
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Creates a fan-out that drops requests arriving within `minimumInterval` of the last one sent.
    // A wedged channel fails every RPC at once; each request dials a replacement connection,
    // so a burst must not become a burst of dials.
    init(
        minimumInterval: Duration = .seconds(5),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.minimumInterval = minimumInterval
        self.now = now
    }

    /// Asks every subscribed resolver to look up the server again, returning whether the request was sent.
    @discardableResult
    func request() -> Bool {
        let continuations = state.withLock { state -> [AsyncStream<Void>.Continuation]? in
            let now = now()
            if let lastSent = state.lastSent, now - lastSent < minimumInterval { return nil }
            state.lastSent = now
            return Array(state.continuations.values)
        }
        guard let continuations else { return false }
        for continuation in continuations {
            continuation.yield()
        }
        return true
    }

    /// A stream that emits once per request sent after it was made.
    func stream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        state.withLock { $0.continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}
