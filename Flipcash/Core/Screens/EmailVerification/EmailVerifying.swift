//
//  EmailVerifying.swift
//  Flipcash
//

import FlipcashCore

/// Public contract for any email-verification implementation. Mirrors
/// `PhoneVerifying` plus a deeplink hook for universal-link-delivered codes.
@MainActor
protocol EmailVerifying: AnyObject, Identifiable {
    /// Fires after the verification email send succeeds. Hosts use this to
    /// advance to the confirm-email screen on their own navigation path.
    var onCodeRequested: (() -> Void)? { get set }

    /// Fires when email verification completes successfully. Hosts use this
    /// to advance past email (e.g. to finish); standalone consumers leave
    /// nil and `await run()` returns.
    var onVerified: (() -> Void)? { get set }

    /// Standalone-mode async entry. Suspends until verified or `cancel()`.
    /// Returns immediately when the profile is already email-verified.
    func run() async throws

    /// Idempotent. Resumes any pending `run()` with `CancellationError`.
    func cancel()

    /// Resets transient input state (entered email, sending flags). Hosts
    /// call this when their navigation path empties.
    func reset()

    /// Applies an out-of-flow deeplink that delivered a verification code.
    /// Idempotent: drops overlapping deeplinks while one is in flight.
    /// Parks the user on the confirm-code screen so the API call's result
    /// has somewhere to surface.
    func applyDeeplinkVerification(_ verification: VerificationDescription)
}
