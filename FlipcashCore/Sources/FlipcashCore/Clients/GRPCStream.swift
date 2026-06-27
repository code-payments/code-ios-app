//
//  GRPCStream.swift
//  FlipcashCore
//

import Foundation
import GRPCCore
import Synchronization

/// v2 replacement for `BidirectionalStreamReference`.
///
/// gRPC v2 streaming is closure-scoped — the `RPCWriter` only exists inside the
/// `requestProducer` closure for the duration of the call. Our consumers
/// (`LiveMintDataStreamer`, `SwapService`, `TransactionService`) instead need a
/// retained handle they can call `sendMessage` on from multiple points after the
/// stream opens. This adapter bridges the two: outbound messages are buffered
/// through an `AsyncStream` that the v2 `requestProducer` drains, and the call
/// runs in a retained `Task`. Cancelling finishes the outbound stream and the task,
/// which tears the RPC down.
///
/// `onComplete` fires exactly once with the terminal result — but NOT when the
/// caller explicitly `cancel()`s, since that is deliberate teardown (e.g. after a
/// terminal response), not a stream error. This prevents a cancel-induced
/// `CancellationError` from delivering a second, spurious completion.
public final class BidirectionalGRPCStream<Request: Sendable, Response: Sendable>: Sendable {

    private struct State {
        var task: Task<Void, Never>?
        var didFinish = false
    }

    private let outbound: AsyncStream<Request>
    private let continuation: AsyncStream<Request>.Continuation
    private let state = Mutex(State())

    public init() {
        (self.outbound, self.continuation) = AsyncStream.makeStream(of: Request.self)
    }

    /// Opens the stream. `perform` runs the concrete v2 RPC: it should drain
    /// `requests` into the call's `RPCWriter` and forward each inbound message to
    /// `onResponse`. The producing/consuming happens inside `perform` so the
    /// generated method's closure scope stays satisfied. Must be called at most
    /// once per instance.
    public func open(
        onResponse: @escaping @Sendable (Response) -> Void,
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void = { _ in },
        perform: @escaping @Sendable (_ requests: AsyncStream<Request>, _ onResponse: @escaping @Sendable (Response) -> Void) async throws -> Void
    ) {
        let requests = outbound
        let task = Task { [weak self] in
            let result: Result<Void, any Error>
            do {
                try await perform(requests, onResponse)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finish(result, onComplete)
        }
        let cancelImmediately = state.withLock { state -> Bool in
            precondition(state.task == nil, "open() called twice on the same stream")
            state.task = task
            return state.didFinish
        }
        if cancelImmediately {
            task.cancel()
        }
    }

    private func finish(_ result: Result<Void, any Error>, _ onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        let alreadyFinished = state.withLock { state -> Bool in
            let was = state.didFinish
            state.didFinish = true
            return was
        }
        guard !alreadyFinished else { return }
        onComplete(result)
    }

    /// Enqueue an outbound message. Safe to call from any point after `open`.
    public func sendMessage(_ request: Request) {
        continuation.yield(request)
    }

    /// Tear the stream down: close the outbound side and cancel the running call.
    /// Suppresses the terminal `onComplete` callback — explicit teardown is not a
    /// stream error.
    public func cancel() {
        let task = state.withLock { state -> Task<Void, Never>? in
            state.didFinish = true
            return state.task
        }
        continuation.finish()
        task?.cancel()
    }

    deinit {
        continuation.finish()
        state.withLock { $0.task }?.cancel()
    }
}

/// v2 replacement for the server-streaming `StreamReference`.
///
/// Server streams have no outbound writer, so this is just a retained, cancellable
/// `Task` running the v2 call whose `onResponse` iterates the inbound messages.
/// Like `BidirectionalGRPCStream`, `onComplete` fires once per open and is
/// suppressed on explicit `cancel()`.
///
/// Unlike the bidirectional adapter, `open` may be called again after the
/// previous call completed — `MessagingService` re-subscribes on the same handle
/// when the server closes the stream, so the `AnyCancellable` held by the caller
/// keeps cancelling the *current* connection. `cancel()` is sticky: once
/// cancelled, later `open` calls are no-ops.
public final class ServerGRPCStream: Sendable {

    private struct State {
        var task: Task<Void, Never>?
        /// Bumped on every `open`. A task's terminal `finish` only delivers
        /// `onComplete` when its generation is still current, so a superseded
        /// connection (re-open while in flight) can never fire a stale
        /// completion or trigger a spurious reconnect.
        var generation = 0
        var didFinish = false
        var isCancelled = false
    }

    private let state = Mutex(State())

    public init() {}

    public func open(
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void = { _ in },
        perform: @escaping @Sendable () async throws -> Void
    ) {
        let generation: Int? = state.withLock { state in
            guard !state.isCancelled else { return nil }
            state.generation += 1
            state.didFinish = false
            return state.generation
        }
        guard let generation else { return }

        let task = Task { [weak self] in
            let result: Result<Void, any Error>
            do {
                try await perform()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finish(generation, result, onComplete)
        }
        let (previousTask, cancelImmediately) = state.withLock { state -> (Task<Void, Never>?, Bool) in
            guard state.generation == generation else { return (nil, true) }
            let previous = state.task
            state.task = task
            return (previous, state.isCancelled)
        }
        previousTask?.cancel()
        if cancelImmediately {
            task.cancel()
        }
    }

    private func finish(_ generation: Int, _ result: Result<Void, any Error>, _ onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        let suppressed = state.withLock { state -> Bool in
            guard state.generation == generation, !state.didFinish, !state.isCancelled else { return true }
            state.didFinish = true
            return false
        }
        guard !suppressed else { return }
        onComplete(result)
    }

    public func cancel() {
        let task = state.withLock { state -> Task<Void, Never>? in
            state.isCancelled = true
            state.didFinish = true
            return state.task
        }
        task?.cancel()
    }

    deinit {
        state.withLock { $0.task }?.cancel()
    }
}
