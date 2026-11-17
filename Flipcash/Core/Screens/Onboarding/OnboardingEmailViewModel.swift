//
//  OnboardingEmailViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onboarding-email")

/// Backs the Group Money onboarding email step. Links the address to the new account without a
/// verification code, then hands control back via ``onComplete``.
///
/// Shaped like ``OnboardingNameViewModel``: onboarding runs before login, so this owns its
/// submission against the in-flight owner instead of reading a session. The linked address is
/// unverified; it does not satisfy the on-ramp's verified-email requirement.
@Observable
@MainActor
final class OnboardingEmailViewModel {

    var enteredEmail: String = ""
    var dialogItem: DialogItem?

    /// Drives the Next button: spinner while saving, then the checkmark.
    private(set) var buttonState: ButtonState = .normal

    /// The account the address is linked to.
    @ObservationIgnored let owner: KeyPair

    @ObservationIgnored private let link: (String, KeyPair) async throws -> Void
    @ObservationIgnored private let validator = EmailValidator()

    /// The submission in flight, for tests to await.
    @ObservationIgnored private(set) var submission: Task<Void, Never>?

    /// Fires once the address is linked; the onboarding flow advances from here.
    @ObservationIgnored var onComplete: (@MainActor () -> Void)?

    // MARK: - Init -

    convenience init(owner: KeyPair, flipClient: FlipClient) {
        self.init(owner: owner) { email, owner in
            try await flipClient.linkUnverifiedEmail(email: email, owner: owner)
        }
    }

    /// - Parameter link: links an address to the owner without verifying it. A seam for tests.
    init(owner: KeyPair, link: @escaping (String, KeyPair) async throws -> Void) {
        self.owner = owner
        self.link = link
    }

    // MARK: - Derived state -

    /// The address that gets submitted, or nil while the input is not an email address.
    var validatedEmail: String? {
        validator.validate(enteredEmail)
    }

    var isSubmitting: Bool {
        !buttonState.isNormal
    }

    var canSubmit: Bool {
        validatedEmail != nil && !isSubmitting
    }

    // MARK: - Submit -

    func submit() {
        guard let email = validatedEmail, !isSubmitting else { return }

        buttonState = .loading
        submission = Task {
            do {
                try await link(email, owner)

                buttonState = .success
                // Same beat the name step holds its checkmark for.
                try? await Task.delay(milliseconds: 500)
                onComplete?()

            } catch ErrorLinkUnverifiedEmail.rejected {
                buttonState = .normal
                logger.info("Email rejected as invalid")
                dialogItem = .error(
                    title: "Invalid Email",
                    subtitle: "Please enter a different email and try again"
                )

            } catch {
                buttonState = .normal
                logger.error("Failed to link email", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to link email during onboarding")
                dialogItem = .error(
                    title: "Something Went Wrong",
                    subtitle: "Please try again later"
                )
            }
        }
    }
}
