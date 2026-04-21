//
//  AsyncStreamBridge.swift
//  FlipcashCore
//

import Foundation
import Combine

/// Converts a Combine-style `Result`-callback subscription into an
/// `AsyncThrowingStream`. When the consumer stops iterating — via `break`,
/// `return`, cancellation, or an early `finish(throwing:)` — `onTermination`
/// calls `cancel()` on the returned `AnyCancellable`, tearing down the
/// underlying subscription.
///
/// This is the shared shape the stream-returning `Client` overloads rely on,
/// and keeps the bridge testable in isolation from gRPC.
///
/// `AnyCancellable` is not `Sendable` and `onTermination` is `@Sendable`,
/// so we use `nonisolated(unsafe)` to cross the boundary. The cancellable
/// is only read after the stream has finished, so there is no concurrent
/// access to protect against.
public func asyncThrowingStream<Value: Sendable>(
    from subscribe: (@escaping @Sendable (Result<Value, Error>) -> Void) -> AnyCancellable
) -> AsyncThrowingStream<Value, Error> {
    AsyncThrowingStream { continuation in
        let cancellable = subscribe { result in
            switch result {
            case .success(let value):
                continuation.yield(value)
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
        nonisolated(unsafe) let unsafeCancellable = cancellable
        continuation.onTermination = { @Sendable _ in
            unsafeCancellable.cancel()
        }
    }
}
