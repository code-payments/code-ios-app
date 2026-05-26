//
//  EmailVerifying.swift
//  Flipcash
//

import FlipcashUI
import FlipcashCore

/// Public contract for any email-verification implementation. Refines
/// `Verifying` with email-specific state, actions, and a deeplink hook for
/// universal-link-delivered codes.
@MainActor
protocol EmailVerifying: Verifying {
    // MARK: - State -

    var enteredEmail: String { get set }

    var verificationPath: [EmailVerificationPath] { get set }

    var sendEmailCodeState: ButtonState { get set }
    var confirmEmailButtonState: ButtonState { get set }

    // MARK: - Derived state -

    var validatedEmail: String? { get }
    var canSendEmailVerification: Bool { get }

    // MARK: - Actions -

    func sendEmailCodeAction()
    func resendEmailCodeAction() async throws

    /// Applies an out-of-flow deeplink that delivered a verification code.
    /// Idempotent: drops overlapping deeplinks while one is in flight.
    func applyDeeplinkVerification(_ verification: VerificationDescription)
}
