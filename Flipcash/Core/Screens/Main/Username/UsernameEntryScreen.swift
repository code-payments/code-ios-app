//
//  UsernameEntryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.username")

/// Claiming a handle, and changing one (Figma node 9442:103254). Shaped after
/// `ProfileNameScreen`, which is the existing screen of this kind — one field,
/// one button.
///
/// It owns its text rather than reading it from the environment the way
/// `ProfileNameScreen` does: that screen shares state with a following photo
/// step, and this flow has no second step.
struct UsernameEntryScreen: View {

    /// Seeds the field when the user already has a handle, so "Change Username"
    /// opens on what they have rather than on an empty box.
    let currentUsername: Username?

    @Environment(Container.self) private var container
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router

    @FocusState private var isFocused: Bool
    @State private var input: String = ""
    @State private var submitTask: Task<Void, Never>?
    @State private var errorDialog: DialogItem?

    private static let validator = UsernameValidator()

    private var isSubmitting: Bool { submitTask != nil }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Enter username")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Username", text: $input)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit(submit)
                    // Lowercases as they type, per the spec's "auto lower case
                    // the username, even if they type upper case". Nothing else
                    // is filtered: Too Short, Too Long and Invalid Characters
                    // are dialogs raised on Next, and a field that refused those
                    // inputs would make three of the six drawn dialogs dead code.
                    .onChange(of: input) { _, latest in
                        let lowered = latest.lowercased()
                        if lowered != latest { input = lowered }
                    }
                    .padding(.top, 32)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("username-field")

                Text("This is how you'll be uniquely identified on the platform")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)

                Spacer()

                Button(action: submit) {
                    if isSubmitting {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.filled)
                // Enabled for anything non-empty, unlike `ProfileNameScreen`'s
                // validity-gated Next: the rejections are the point of the
                // button here, so it has to be reachable while the input is bad.
                .disabled(input.isEmpty || isSubmitting)
                .accessibilityIdentifier("username-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
        .onAppear {
            input = currentUsername?.value ?? ""
            isFocused = true
        }
        // Leaving abandons the submission: its only continuation pops a stack
        // this screen no longer sits on.
        .onDisappear { submitTask?.cancel() }
    }

    /// The server's minimum in USD, or nil before user flags have loaded.
    private var minimumBalance: FiatAmount? {
        guard let minimum = session.userFlags?.usernameMinBalance else { return nil }
        return .usd(minimum.decimalValue)
    }

    private func submit() {
        guard !isSubmitting else { return }

        if let failure = Self.validator.failure(for: input) {
            errorDialog = .usernameValidation(failure)
            return
        }

        guard let username = Self.validator.validate(input) else { return }

        submitTask = Task {
            defer { submitTask = nil }

            do {
                try await container.flipClient.setUsername(
                    username,
                    owner: session.ownerKeyPair
                )
                try await session.updateProfile()

                guard !Task.isCancelled else { return }
                router.popTopmost()

            } catch let error as ErrorProfile {
                guard !Task.isCancelled else { return }
                logger.info("Username rejected", metadata: ["error": "\(error)"])

                // Captured unconditionally: `ErrorProfile.reportingLevel` already
                // files every rejection as `.info` — a breadcrumb, never a page —
                // and only `.unknown` as `.error`. Gating the call here would
                // duplicate that classification in a second place.
                ErrorReporting.captureError(error, reason: "Failed to set username")

                errorDialog = .usernameSubmission(error, minimum: minimumBalance) {
                    router.presentAddMoney(.general, source: .usernameShortfall)
                }

            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to set username", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to set username")
                errorDialog = .usernameGenericFailure
            }
        }
    }
}
