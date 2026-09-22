//
//  EditGroupIconScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-icon")

/// Replaces a group's picture. The Icon row's destination (node 10187:110373), drawn the way
/// ``ProfilePhotoScreen`` draws the profile photo: the picture itself is the picker.
struct EditGroupIconScreen: View {

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

    /// Drives Save: spinner while uploading, then the checkmark the rest of the app shows on a
    /// completed action.
    @State private var buttonState: ButtonState = .normal

    /// The picture already on the group, so the screen opens on what it is about to replace rather
    /// than on an empty circle. Drawn but never submitted — Save stays shut until a new one is
    /// picked.
    @State private var currentIcon: UIImage?

    private static let avatarSize: CGFloat = 158
    private static let plusSize: CGFloat = 64

    private var isSubmitting: Bool { submitTask != nil }

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()

                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isShowingPhotoPicker = true }
                    Button("Choose File", systemImage: "folder") { isShowingFilePicker = true }
                } label: {
                    CircleImage(
                        image: model.picture ?? currentIcon,
                        size: Self.avatarSize,
                        plusSize: Self.plusSize
                    )
                }
                .menuIndicator(.hidden)
                .disabled(isSubmitting)
                .accessibilityIdentifier("edit-group-icon-picker")

                if let title = conversation?.title {
                    Text(title)
                        .font(.appDisplayCompact)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .padding(.top, 21)
                }

                Spacer()

                Button(action: submit) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                // The checkmark hold keeps the picture selected, so the button needs the state to
                // stay shut against a second submission.
                .disabled(!model.canSavePicture || !buttonState.isNormal || isSubmitting)
                .accessibilityIdentifier("edit-group-icon-save-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Icon")
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
        // Keyed on the blob so a picture that changes underneath — including the one this screen
        // just saved — is what the circle ends up drawing.
        .task(id: conversation?.picture?.thumbnailBlobID) {
            currentIcon = await ProfilePictureLoader.thumbnail(
                for: conversation?.picture,
                using: container.flipClient,
                owner: sessionContainer.session.ownerKeyPair
            )
        }
        .onDisappear { submitTask?.cancel() }
    }

    private func submit() {
        guard model.canSavePicture, !isSubmitting else { return }

        buttonState = .loading

        submitTask = Task {
            defer { submitTask = nil }

            do {
                let conversation = try await model.savePicture(
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
    /// wherever a group picture is submitted.
    private func handle(_ error: Error) {
        guard !Task.isCancelled else { return }

        switch error {
        case ErrorEditChat.pictureBlobNotAccepted:
            logger.info("Group picture not accepted")
            ErrorReporting.captureError(error, reason: "Group picture not accepted")
            dialog = .error(
                title: "This Photo Isn't Allowed",
                subtitle: "Try a different photo"
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

        case let blobError as ErrorBlob:
            logger.info("Group picture upload failed", metadata: ["error": "\(blobError)"])
            ErrorReporting.captureError(blobError, reason: "Group picture upload failed", userFacing: true)
            dialog = .profilePictureFailed(blobError)

        case let encoderError as ImageEncoderError:
            logger.error("Failed to encode the group picture", metadata: ["error": "\(encoderError)"])
            ErrorReporting.captureError(encoderError, reason: "Failed to encode the group picture")
            dialog = .imageProcessingFailed

        default:
            logger.error("Failed to edit group icon", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to edit group icon")
            dialog = .error(
                title: "Couldn't Save This Photo",
                subtitle: "Try again"
            )
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            logger.info("Group icon file import failed", metadata: ["error": "\(error)"])
            return

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
