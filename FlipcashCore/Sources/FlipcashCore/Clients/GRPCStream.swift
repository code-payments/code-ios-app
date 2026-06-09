//
//  GRPCStream.swift
//  FlipcashCore
//

import Foundation
import GRPCCore

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
public final class BidirectionalGRPCStream<Request: Sendable, Response: Sendable>: @unchecked Sendable {

    private let outbound: AsyncStream<Request>
    private let continuation: AsyncStream<Request>.Continuation
    private let lock = NSLock()
    private var didFinish = false
    private var task: Task<Void, Never>?

    public init() {
        (self.outbound, self.continuation) = AsyncStream.makeStream(of: Request.self)
    }

    /// Opens the stream. `perform` runs the concrete v2 RPC: it should drain
    /// `requests` into the call's `RPCWriter` and forward each inbound message to
    /// `onResponse`. The producing/consuming happens inside `perform` so the
    /// generated method's closure scope stays satisfied.
    public func open(
        onResponse: @escaping @Sendable (Response) -> Void,
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void = { _ in },
        perform: @escaping @Sendable (_ requests: AsyncStream<Request>, _ onResponse: @escaping @Sendable (Response) -> Void) async throws -> Void
    ) {
        let requests = outbound
        task = Task { [weak self] in
            let result: Result<Void, any Error>
            do {
                try await perform(requests, onResponse)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finish(result, onComplete)
        }
    }

    private func finish(_ result: Result<Void, any Error>, _ onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        lock.lock()
        let alreadyFinished = didFinish
        didFinish = true
        lock.unlock()
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
        lock.lock()
        didFinish = true
        lock.unlock()
        continuation.finish()
        task?.cancel()
    }

    deinit {
        continuation.finish()
        task?.cancel()
    }
}

/// v2 replacement for the server-streaming `StreamReference`.
///
/// Server streams have no outbound writer, so this is just a retained, cancellable
/// `Task` running the v2 call whose `onResponse` iterates the inbound messages.
/// Like `BidirectionalGRPCStream`, `onComplete` fires once and is suppressed on
/// explicit `cancel()`.
public final class ServerGRPCStream: @unchecked Sendable {

    private let lock = NSLock()
    private var didFinish = false
    private var task: Task<Void, Never>?

    public init() {}

    public func open(
        onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void = { _ in },
        perform: @escaping @Sendable () async throws -> Void
    ) {
        task = Task { [weak self] in
            let result: Result<Void, any Error>
            do {
                try await perform()
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finish(result, onComplete)
        }
    }

    private func finish(_ result: Result<Void, any Error>, _ onComplete: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        lock.lock()
        let alreadyFinished = didFinish
        didFinish = true
        lock.unlock()
        guard !alreadyFinished else { return }
        onComplete(result)
    }

    public func cancel() {
        lock.lock()
        didFinish = true
        lock.unlock()
        task?.cancel()
    }

    deinit {
        task?.cancel()
    }
}
