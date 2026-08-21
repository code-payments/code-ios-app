//
//  OnboardingNameViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.onboarding-name")

/// Backs the onboarding display-name step. Collects and submits the name the
/// account needs for tips and chat, then hands control back via ``onComplete``.
///
/// This mirrors the tip-card `ProfileNameScreen`, but the tip-card screen is
/// session-scoped (it reads `SessionContainer`/`AppRouter`); onboarding runs
/// pre-login, so this owns its own submission against the in-flight owner.
@Observable
@MainActor
final class OnboardingNameViewModel {

    var displayName: String = ""
    var dialogItem: DialogItem?

    private(set) var isSubmitting: Bool = false

    @ObservationIgnored private let flipClient: FlipClient
    @ObservationIgnored private let owner: KeyPair
    @ObservationIgnored private let validator = DisplayNameValidator()

    /// Fires once the name is saved; the onboarding flow advances from here.
    @ObservationIgnored var onComplete: (@MainActor () -> Void)?

    // MARK: - Init -

    init(owner: KeyPair, flipClient: FlipClient) {
        self.owner = owner
        self.flipClient = flipClient
    }

    // MARK: - Derived state -

    /// The name accepted by `SetDisplayName`, or nil while the input is invalid.
    /// This exact string is what gets submitted.
    var validatedDisplayName: String? {
        validator.validate(displayName)
    }

    var remainingCharacters: Int {
        validator.remaining(in: displayName)
    }

    // MARK: - Submit -

    func submit() {
        guard let name = validatedDisplayName, !isSubmitting else { return }

        isSubmitting = true
        Task {
            defer { isSubmitting = false }

            do {
                try await flipClient.setDisplayName(name, owner: owner)
                // Onboarding runs pre-login against a brand-new account, so there is
                // never a prior name here — this is always a first set.
                Analytics.displayNameSubmitted(source: .onboarding, hadPreviousName: false)
                onComplete?()

            } catch ErrorProfile.moderated(let category) {
                logger.info("Display name moderation denied", metadata: ["category": "\(category)"])
                dialogItem = .error(
                    title: "This Name is Not Allowed",
                    subtitle: "Try a different name"
                )

            } catch ErrorProfile.invalidDisplayName {
                logger.info("Display name rejected as invalid")
                dialogItem = .error(
                    title: "This Name Isn't Valid",
                    subtitle: "Try a different name"
                )

            } catch {
                logger.error("Failed to set display name", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to set display name during onboarding")
                dialogItem = .error(
                    title: "Couldn't Save Your Name",
                    subtitle: "Try again"
                )
            }
        }
    }
}
