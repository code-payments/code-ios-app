//
//  OnrampVerificationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Drives the Coinbase onramp KYC flow: phone verification → email
/// verification → KYC info collection. Composes a `PhoneVerificationViewModel`
/// and an `EmailVerificationViewModel`, wires their callbacks to drive the
/// shared `OnrampVerificationPath`, and owns the continuation lifecycle that
/// callers `await` via `run()`.
///
/// `Identifiable` so callers can drive `.sheet(item:)` directly with an
/// optional viewmodel binding — no separate `isPresented` flag needed.
@Observable
@MainActor
final class OnrampVerificationViewModel: Identifiable {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                phoneViewModel.reset()
                emailViewModel.reset()
            }
        }
    }

    // MARK: - Composed verifiers -

    let phoneViewModel: PhoneVerificationViewModel
    let emailViewModel: EmailVerificationViewModel

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session

    // MARK: - Run continuation -

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Init -

    init(session: Session, flipClient: FlipClient) {
        self.session = session
        self.phoneViewModel = PhoneVerificationViewModel(session: session, flipClient: flipClient)
        self.emailViewModel = EmailVerificationViewModel(session: session, flipClient: flipClient)

        phoneViewModel.onCodeRequested = { [weak self] in
            guard let self else { return }
            verificationPath.append(.confirmPhoneNumberCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)
        }
        phoneViewModel.onVerified = { [weak self] in
            self?.navigateToEmailOrFinish()
        }
        emailViewModel.onCodeRequested = { [weak self] in
            guard let self else { return }
            verificationPath.append(.confirmEmailCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmEmail)
        }
        emailViewModel.onVerified = { [weak self] in
            self?.finish()
        }
    }

    isolated deinit {
        // Failsafe: a viewmodel discarded mid-flow without an explicit cancel
        // would otherwise leave the caller's `await run()` suspended forever.
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    // MARK: - Async entry -

    /// Suspends until both phone and email are verified, then returns.
    /// Throws `CancellationError` if `cancel()` fires (user dismisses the
    /// sheet). Returns immediately if the profile is already fully verified.
    /// Must not be called concurrently on the same viewmodel — assertion
    /// fires in debug; in release the new call resumes with `CancellationError`
    /// so the caller observes a consistent failure rather than hanging.
    func run() async throws {
        if isAccountVerified { return }
        assert(continuation == nil, "OnrampVerificationViewModel.run() called while another awaiter is suspended")
        guard continuation == nil else { throw CancellationError() }
        try await withCheckedThrowingContinuation { c in
            continuation = c
        }
    }

    /// Idempotent. Called by the sheet host when the user dismisses the
    /// verification sheet, or directly by callers that want to tear down
    /// the flow. Cancels both inner verifiers (idempotent in wrapped mode)
    /// and resumes any pending `run()` with `CancellationError`.
    func cancel() {
        phoneViewModel.cancel()
        emailViewModel.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    private func finish() {
        let c = continuation
        continuation = nil
        c?.resume()
    }

    // MARK: - Navigation -

    /// Entry point invoked by `VerifyInfoScreen`'s Next button.
    func navigateToInitialVerification() {
        if !isPhoneVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            verificationPath.append(.enterPhoneNumber)
            return
        }

        navigateToEmailOrFinish()
    }

    private func navigateToEmailOrFinish() {
        if !isEmailVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            verificationPath.append(.enterEmail)
            return
        }

        finish()
    }

    // MARK: - Deeplinks -

    /// Forwarded to the inner email viewmodel; deeplinks are email-only.
    /// Resets the shared navigation path to `[.confirmEmailCode]` so the
    /// API call's result has somewhere to surface — preserves the
    /// pre-extraction behavior where the deeplink replaces (not appends to)
    /// the current path.
    func applyDeeplinkVerification(_ verification: VerificationDescription) {
        if verificationPath.last != .confirmEmailCode {
            verificationPath = [.confirmEmailCode]
        }
        emailViewModel.applyDeeplinkVerification(verification)
    }

    // MARK: - Derived state -

    private var isPhoneVerified: Bool {
        session.profile?.isPhoneVerified ?? false
    }

    private var isEmailVerified: Bool {
        session.profile?.isEmailVerified ?? false
    }

    private var isAccountVerified: Bool {
        isPhoneVerified && isEmailVerified
    }
}
