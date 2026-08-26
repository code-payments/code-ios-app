//
//  ProfileNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.profile-name")

struct ProfileNameScreen: View {

    /// Where a saved name leads.
    enum Completion {
        /// Profile setup: on to the tip card the name unlocks.
        case tipcard
        /// A lone edit: back to the screen that opened this one.
        case back
    }

    var completion: Completion = .tipcard

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ProfileCreationState.self) private var state

    @FocusState private var isNameFocused: Bool
    @State private var submitTask: Task<Void, Never>?
    @State private var errorDialog: DialogItem?

    /// Drives the Next button: spinner while saving, then the checkmark the
    /// rest of the app shows on a completed action.
    @State private var buttonState: ButtonState = .normal

    /// True while the submission is in flight, including the checkmark hold at
    /// the end of it, so the field stays locked through the confirmation.
    private var isSubmitting: Bool { submitTask != nil }

    /// Shown only once the limit is close enough to explain a disabled Next.
    private static let countdownThreshold = 10

    var body: some View {
        @Bindable var state = state

        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's your name?")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Your Name", text: $state.displayName)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isNameFocused)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .onSubmit(submit)
                    .padding(.top, 32)
                    .disabled(isSubmitting)

                Text("This is how you'll appear to others")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)

                Spacer()

                if state.remainingCharacters < Self.countdownThreshold {
                    Text("\(state.remainingCharacters) characters")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                Button(action: submit) {
                    ButtonStateLabel("Next", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(state.validatedDisplayName == nil || isSubmitting)
                .accessibilityIdentifier("profile-name-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
        .onAppear { isNameFocused = true }
        // Leaving the screen abandons the submission: its only continuation is a
        // push onto a stack this screen no longer sits on.
        .onDisappear { submitTask?.cancel() }
    }

    private func submit() {
        guard let name = state.validatedDisplayName, !isSubmitting else { return }

        // Read before the RPC: `updateProfile()` below installs the new name, after
        // which every submission would look like a replacement.
        let hadPreviousName = !(sessionContainer.session.profile?.displayName ?? "").isEmpty
        let source: Analytics.DisplayNameSource = switch completion {
        case .tipcard: .tipCardSetup
        case .back:    .myAccount
        }

        buttonState = .loading
        submitTask = Task {
            defer { submitTask = nil }

            do {
                try await container.flipClient.setDisplayName(
                    name,
                    owner: sessionContainer.session.ownerKeyPair
                )
                Analytics.displayNameSubmitted(source: source, hadPreviousName: hadPreviousName)
                try await sessionContainer.session.updateProfile()

                buttonState = .success
                // Same beat onboarding holds its checkmark for, so the
                // confirmation is seen before the screen changes.
                try? await Task.delay(milliseconds: 500)

                guard !Task.isCancelled else { return }

                switch completion {
                case .tipcard:
                    // `push` resolves the stack when it runs, and this runs after two
                    // RPCs — by now the user may have swapped to another sheet, whose
                    // stack has no profile-creation state to mount against.
                    guard router.presentedSheet?.stack == .tips else { return }
                    // The photo-capture step is skipped for now — the card omits the
                    // profile photo, so setup goes straight from the name to the card.
                    router.push(.tipcard)
                case .back:
                    router.popTopmost()
                }

            } catch ErrorProfile.moderated(let category) {
                buttonState = .normal
                logger.info("Display name moderation denied", metadata: ["category": "\(category)"])
                errorDialog = .error(
                    title: "This Name is Not Allowed",
                    subtitle: "Try a different name"
                )

            } catch ErrorProfile.invalidDisplayName {
                buttonState = .normal
                logger.info("Display name rejected as invalid")
                errorDialog = .error(
                    title: "This Name Isn't Valid",
                    subtitle: "Try a different name"
                )

            } catch {
                buttonState = .normal
                guard !Task.isCancelled else { return }
                logger.error("Failed to set display name", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to set display name")
                errorDialog = .error(
                    title: "Couldn't Save Your Name",
                    subtitle: "Try again"
                )
            }
        }
    }
}
