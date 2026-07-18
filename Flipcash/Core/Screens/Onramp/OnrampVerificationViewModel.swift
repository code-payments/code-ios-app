//
//  OnrampVerificationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Drives the Coinbase onramp KYC flow: phone verification → email
/// verification → KYC info collection. Generic over the verifier types so
/// callers, tests, and previews can substitute any `PhoneVerifying` /
/// `EmailVerifying` conformer. Wires their callbacks to drive the shared
/// `OnrampVerificationPath`, and owns its own continuation via the
/// `Verifying` base extension.
@Observable
@MainActor
final class OnrampVerificationViewModel<P: PhoneVerifying, E: EmailVerifying>: Verifying {

    nonisolated let id = UUID()

    // MARK: - View state -

    var verificationPath: [OnrampVerificationPath] = [] {
        didSet {
            if verificationPath.isEmpty && !oldValue.isEmpty {
                phoneVerifier.reset()
                emailVerifier.reset()
            }
        }
    }

    var dialogItem: DialogItem?

    /// Onramp doesn't surface a resend control of its own — defers to whichever
    /// inner verifier is currently active. Kept on the protocol for symmetry.
    var isResending: Bool {
        phoneVerifier.isResending || emailVerifier.isResending
    }

    // MARK: - Composed verifiers (DI) -

    let phoneVerifier: P
    let emailVerifier: E

    // MARK: - Dependencies -

    @ObservationIgnored private let session: Session

    // MARK: - Verifying lifecycle hooks -

    @ObservationIgnored var onCodeRequested: (@MainActor () -> Void)?
    @ObservationIgnored var onVerified: (@MainActor () -> Void)?

    /// Internal hook for the `Verifying` default `run`/`cancel`/`finish`
    /// implementations.
    @ObservationIgnored var continuation: CheckedContinuation<Void, Error>?

    // MARK: - Init -

    /// Primary DI init — accepts any conformers of the verifier protocols.
    /// Tests and previews construct their own conformers and inject them here.
    init(
        session: Session,
        phoneVerifier: P,
        emailVerifier: E
    ) {
        self.session = session
        self.phoneVerifier = phoneVerifier
        self.emailVerifier = emailVerifier

        phoneVerifier.onCodeRequested = { [weak self] in
            guard let self else { return }
            verificationPath.append(.confirmPhoneNumberCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmPhone)
        }
        phoneVerifier.onVerified = { [weak self] in
            self?.navigateToEmailOrFinish()
        }
        emailVerifier.onCodeRequested = { [weak self] in
            guard let self else { return }
            verificationPath.append(.confirmEmailCode)
            Analytics.track(event: Analytics.OnrampEvent.showConfirmEmail)
        }
        emailVerifier.onVerified = { [weak self] in
            self?.finish()
        }
    }

    // `@_optimize(none)` skips the SIL optimizer for this deinit. Without it,
    // Swift 6.3's `EarlyPerfInliner` crashes when checking layout-constraint
    // compatibility through the generic parameters of this class on `-O`
    // archive builds.
    @_optimize(none)
    isolated deinit {
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    /// Onramp overrides the base `cancel()` to cascade through the inner
    /// verifiers (idempotent for inner continuations in wrapped mode; needed
    /// to reach the inner email verifier's deeplink task).
    func cancel() {
        phoneVerifier.cancel()
        emailVerifier.cancel()
        let c = continuation
        continuation = nil
        c?.resume(throwing: CancellationError())
    }

    func reset() {
        phoneVerifier.reset()
        emailVerifier.reset()
    }

    // MARK: - Verifying contract -

    var isAlreadyVerified: Bool {
        phoneVerifier.isAlreadyVerified && emailVerifier.isAlreadyVerified
    }

    // MARK: - Navigation -

    /// The first screen the verification sheet shows — phone if unverified
    /// (unlikely), email otherwise. The sheet's root IS the first step;
    /// there is no intro page.
    func initialStep() -> OnrampVerificationPath {
        if !phoneVerifier.isAlreadyVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterPhone)
            return .enterPhoneNumber
        }
        Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
        return .enterEmail
    }

    private func navigateToEmailOrFinish() {
        if !emailVerifier.isAlreadyVerified {
            Analytics.track(event: Analytics.OnrampEvent.showEnterEmail)
            verificationPath.append(.enterEmail)
            return
        }

        finish()
    }

    // MARK: - Deeplinks -

    /// Forwards to the inner email verifier and parks the user on the
    /// confirm-email screen. Guards on the inner state BEFORE mutating the
    /// shared path so a deeplink that the inner verifier would drop
    /// (already verified, or another deeplink in flight) doesn't yank the
    /// user off their current step.
    func applyDeeplinkVerification(_ verification: VerificationDescription) {
        guard !emailVerifier.isAlreadyVerified else { return }
        if verificationPath.last != .confirmEmailCode {
            verificationPath = [.confirmEmailCode]
        }
        emailVerifier.applyDeeplinkVerification(verification)
    }
}

// MARK: - Production wiring -

/// Default concrete combination of phone + email verifiers. Use this
/// typealias at storage sites (e.g. `AddMoneyAmountViewModel`) so they
/// don't have to spell out the generic parameters.
typealias OnrampVerification = OnrampVerificationViewModel<
    PhoneVerificationViewModel,
    EmailVerificationViewModel
>

extension OnrampVerificationViewModel
    where P == PhoneVerificationViewModel, E == EmailVerificationViewModel
{
    /// Convenience init for the production path: constructs concrete
    /// verifiers from the session + flipClient and wires them.
    convenience init(session: Session, flipClient: FlipClient) {
        self.init(
            session: session,
            phoneVerifier: PhoneVerificationViewModel(
                owner: session.ownerKeyPair,
                flipClient: flipClient,
                isAlreadyVerified: { [weak session] in session?.profile?.isPhoneVerified ?? false },
                onShouldRefreshProfile: { [weak session] in try? await session?.updateProfile() },
            ),
            emailVerifier: EmailVerificationViewModel(session: session, flipClient: flipClient)
        )
    }
}
