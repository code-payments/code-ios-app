//
//  PhoneVerifying.swift
//  Flipcash
//

/// Public contract for any phone-verification implementation. Hosts (e.g.
/// `OnrampVerificationViewModel`) wire callbacks and drive their own
/// navigation; standalone consumers (e.g. a Send-side sheet) `await run()`
/// and ignore the callbacks.
@MainActor
protocol PhoneVerifying: AnyObject, Identifiable {
    /// Fires after the SMS verification code request succeeds. Hosts use
    /// this to advance to the confirm-code screen on their own navigation
    /// path. Standalone consumers leave nil.
    var onCodeRequested: (() -> Void)? { get set }

    /// Fires when phone verification completes successfully. Hosts use this
    /// to advance past phone (e.g. to email); standalone consumers leave
    /// nil and `await run()` returns.
    var onVerified: (() -> Void)? { get set }

    /// Standalone-mode async entry. Suspends until verified or `cancel()`.
    /// Returns immediately when the profile is already phone-verified.
    /// Throws `CancellationError` on cancel. Hosts that wrap via callbacks
    /// never call this — they own the awaited lifecycle themselves.
    func run() async throws

    /// Idempotent. Resumes any pending `run()` with `CancellationError`.
    /// Safe to call in wrapped mode (no-op when no continuation exists).
    func cancel()

    /// Resets transient input state (entered phone, entered code, sending
    /// flags). Hosts call this when their navigation path empties.
    func reset()
}
