//
//  EditGroupCoverScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-cover")

/// Replaces a group's cover banner, pushed from Edit Group's cover. Drawn the way
/// ``ChangeCoverPictureScreen`` draws the profile cover: the banner itself is the picker.
struct EditGroupCoverScreen: View {

    let conversationID: ConversationID

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var model = EditGroupModel()
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var submitTask: Task<Void, Never>?
    @State private var dialog: DialogItem?
    @State private var buttonState: ButtonState = .normal

    private var isSubmitting: Bool { submitTask != nil }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isShowingPhotoPicker = true }
                    Button("Choose File", systemImage: "folder") { isShowingFilePicker = true }
                } label: {
                    ProfileCoverBanner(
                        cover: .group(conversationID, picture: conversation?.coverPicture),
                        preview: model.picture
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius))
                    .overlay {
                        if model.picture == nil && conversation?.coverPicture == nil {
                            Image(systemName: "plus")
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .menuIndicator(.hidden)
                .disabled(isSubmitting)
                .accessibilityIdentifier("edit-group-cover-picker")
                .padding(.top, 20)

                Spacer()

                Button(action: submit) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                // The checkmark hold keeps the cover selected, so the button needs the state to stay
                // shut against a second submission.
                .disabled(!model.canSavePicture || !buttonState.isNormal || isSubmitting)
                .accessibilityIdentifier("edit-group-cover-save-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Cover")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .fullScreenCover(isPresented: $isShowingPhotoPicker) {
            ImagePickerWithEditor(
                onImagePicked: model.select(picture:),
                onDismiss: { isShowingPhotoPicker = false }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onDisappear { submitTask?.cancel() }
    }

    /// Save proposes; the dialog commits, as it does for the group's picture.
    private func submit() {
        guard model.canSavePicture, !isSubmitting else { return }

        dialog = .confirmGroupChange(.cover) { save() }
    }

    private func save() {
        buttonState = .loading

        submitTask = Task {
            defer { submitTask = nil }

            do {
                let conversation = try await model.saveCover(
                    for: conversationID,
                    using: SessionGroupChatEditor(
                        session: sessionContainer.session,
                        flipClient: container.flipClient
                    )
                )

                conversationController.applyEdit(conversation)

                buttonState = .success
                try? await Task.delay(milliseconds: 500)

                guard !Task.isCancelled else { return }
                router.popTopmost()

            } catch {
                buttonState = .normal
                guard !Task.isCancelled else { return }
                dialog = .groupImageEditFailed(error, image: .cover)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            logger.info("Group cover file import failed", metadata: ["error": "\(error)"])

        case .success(let urls):
            guard let url = urls.first else { return }
            importImage(at: url)
        }
    }

    private func importImage(at url: URL) {
        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value

            guard let image else {
                dialog = .imageProcessingFailed
                return
            }

            model.select(picture: image)
        }
    }
}
