//
//  Verifying.swift
//  Flipcash
//

import Observation
import FlipcashUI

/// Base contract for any verification flow (phone, email, future variants).
/// Refines `Observation.Observable` so generic views can use `@Bindable` on
/// a `VM: Verifying`. Hosts that compose a verifier wire the callbacks;
/// standalone consumers `await run()` and leave callbacks nil.
///
/// The continuation requirement is exposed so the default `run`/`cancel`/
/// `finish` implementations (in the extension below) can drive it. Treat it
/// as an internal hook — outside callers go through `run` and `cancel`.
@MainActor
protocol Verifying: AnyObject, Identifiable, Observable {
    /// Fires after a verification code request succeeds (e.g. SMS sent,
    /// email sent). Hosts use this to advance their own navigation path.
    var onCodeRequested: (@MainActor () -> Void)? { get set }

    /// Fires when verification completes successfully. Hosts use this to
    /// advance past this step; standalone consumers leave nil and `await
    /// run()` returns.
    var onVerified: (@MainActor () -> Void)? { get set }

    var dialogItem: DialogItem? { get set }
    var isResending: Bool { get }

    /// Continuation slot used by the default `run` / `cancel` / `finish`
    /// implementations. Internal hook — not for outside callers.
    var continuation: CheckedContinuation<Void, Error>? { get set }

    /// `true` when the underlying profile is already verified for this
    /// channel, so `run()` short-circuits without suspending.
    var isAlreadyVerified: Bool { get }

    /// Clears transient input state (entered values, sending flags).
    func reset()
}

extension Verifying {
    /// Suspends until verified or `cancel()` fires. Returns immediately if
    /// already verified. Throws `CancellationError` on cancel. Hosts that
    /// compose via callbacks never call this — they own the awaited
    /// lifecycle themselves.
    func run() async throws {
        if isAlreadyVerified { return }
        guard continuation == nil else { throw CancellationError() }
        try await withCheckedThrowingContinuation { c in
            continuation = c
        }
    }

    /// Idempotent. Resumes any pending `run()` with `CancellationError`.
    func cancel() {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    /// Resumes any pending `run()` with success. Called by conformers from
    /// their post-success branch when no host callback is set.
    func finish() {
        let c = continuation
        continuation = nil
        c?.resume()
    }
}
