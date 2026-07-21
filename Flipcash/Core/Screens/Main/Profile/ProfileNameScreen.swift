//
//  ProfileNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.profile-name")

struct ProfileNameScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ProfileCreationState.self) private var state

    @FocusState private var isNameFocused: Bool
    @State private var isSubmitting = false
    @State private var errorDialog: DialogItem?

    /// Shown only once the limit is close enough to explain a disabled Next.
    private static let countdownThreshold = 10

    var body: some View {
        @Bindable var state = state

        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("What is your name?")
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

                Spacer()

                if state.remainingCharacters < Self.countdownThreshold {
                    Text("\(state.remainingCharacters) characters")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                Button(action: submit) {
                    if isSubmitting {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.filled)
                .disabled(!state.isDisplayNameValid || isSubmitting)
                .accessibilityIdentifier("profile-name-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
        .onAppear { isNameFocused = true }
    }

    private func submit() {
        guard let name = state.validatedDisplayName, !isSubmitting else { return }

        isSubmitting = true
        Task {
            defer { isSubmitting = false }

            do {
                try await container.flipClient.setDisplayName(
                    name,
                    owner: sessionContainer.session.ownerKeyPair
                )
                try await sessionContainer.session.updateProfile()
                router.push(.profilePhoto)

            } catch ErrorProfile.moderated(let category) {
                logger.info("Display name moderation denied", metadata: ["category": "\(category)"])
                errorDialog = .error(
                    title: "This Name is Not Allowed",
                    subtitle: "Try a different name"
                )

            } catch ErrorProfile.invalidDisplayName {
                logger.info("Display name rejected as invalid")
                errorDialog = .error(
                    title: "This Name Isn't Valid",
                    subtitle: "Try a different name"
                )

            } catch {
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
