//
//  EditGroupNameScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-name")

/// Renames a group. The Name row's destination (node 10187:110373), drawn the way
/// ``ProfileNameScreen`` draws the display name: one field, a countdown near the cap, and a Save
/// that wears its own progress.
struct EditGroupNameScreen: View {

    let conversationID: ConversationID

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var model: EditGroupModel
    @State private var submitTask: Task<Void, Never>?
    @State private var dialog: DialogItem?

    /// Drives Save: spinner while saving, then the checkmark the rest of the app shows on a
    /// completed action.
    @State private var buttonState: ButtonState = .normal

    @FocusState private var isNameFocused: Bool

    /// Shown only once the limit is close enough to explain a disabled Save. Matches the
    /// display-name field's countdown and the new-group form's.
    private static let countdownThreshold = 10

    init(conversationID: ConversationID, currentTitle: String) {
        self.conversationID = conversationID
        // Seeded here rather than in `.onAppear` so the field opens on the name it is about to
        // replace instead of animating it in over the push.
        _model = State(initialValue: EditGroupModel(title: currentTitle))
    }

    /// True while the submission is in flight, including the checkmark hold at the end of it, so
    /// the field stays locked through the confirmation.
    private var isSubmitting: Bool { submitTask != nil }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    var body: some View {
        @Bindable var model = model

        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Group Name", text: $model.title)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .padding(.top, 32)
                    .disabled(isSubmitting)

                Text("This is how the group appears to everyone in it")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)

                Spacer()

                if model.remainingTitleScalars < Self.countdownThreshold {
                    Text("\(model.remainingTitleScalars) characters")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                }

                Button(action: submit) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!model.canSaveTitle(currentTitle: conversation?.title) || isSubmitting)
                .accessibilityIdentifier("edit-group-name-save-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Name")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .onAppear { isNameFocused = true }
        // Leaving the screen abandons the submission: its only continuation is a pop off a stack
        // this screen no longer sits on.
        .onDisappear { submitTask?.cancel() }
    }

    private func submit() {
        guard model.canSaveTitle(currentTitle: conversation?.title), !isSubmitting else { return }

        isNameFocused = false
        buttonState = .loading

        submitTask = Task {
            defer { submitTask = nil }

            do {
                let conversation = try await model.saveTitle(
                    for: conversationID,
                    using: SessionGroupChatEditor(
                        session: sessionContainer.session,
                        flipClient: container.flipClient
                    )
                )

                // The response carries the post-edit metadata, so the store is seated from it
                // rather than from a refetch.
                conversationController.applyEdit(conversation)

                buttonState = .success
                // Same beat the rest of the app holds its checkmark for.
                try? await Task.delay(milliseconds: 500)

                guard !Task.isCancelled else { return }
                router.popTopmost()

            } catch {
                buttonState = .normal
                handle(error)
            }
        }
    }

    /// Mirrors ``NewPublicGroupScreen``'s mapping so the same server answer reads the same way
    /// wherever a group name is submitted.
    ///
    /// Every case leaves the user on this screen with the field as they typed it, which is what a
    /// moderated name needs: the only way forward is to amend it here.
    private func handle(_ error: Error) {
        guard !Task.isCancelled else { return }

        switch error {
        case ErrorEditChat.titleModerated(let category):
            logger.info("Group title moderation denied", metadata: ["category": "\(category)"])
            ErrorReporting.captureError(error, reason: "Group title moderation denied")
            dialog = .error(
                title: "This Name is Not Allowed",
                subtitle: "Try a different group name"
            )

        case ErrorEditChat.denied:
            logger.info("Group edit denied")
            ErrorReporting.captureError(error, reason: "Group edit denied")
            dialog = .error(
                title: "You Can't Edit This Group",
                subtitle: "Try again later"
            )

        case ErrorEditChat.notFound:
            logger.info("Group edit target not found")
            ErrorReporting.captureError(error, reason: "Group edit target not found")
            dialog = .error(
                title: "This Group No Longer Exists",
                subtitle: "It may have been deleted"
            )

        default:
            logger.error("Failed to edit group name", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to edit group name")
            dialog = .error(
                title: "Couldn't Save This Name",
                subtitle: "Try again"
            )
        }
    }
}
