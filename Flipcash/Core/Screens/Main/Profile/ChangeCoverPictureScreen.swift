//
//  ChangeCoverPictureScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.profile-cover")

/// Changing the cover banner on its own, pushed from Edit Profile. Owns its upload state so a
/// cover can never resume an avatar blob.
struct ChangeCoverPictureScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    @State private var state = ProfileCreationState()
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var dialog: DialogItem?
    @State private var buttonState: ButtonState = .normal

    private var session: Session { sessionContainer.session }
    private var profile: Profile? { session.profile }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isShowingPhotoPicker = true }
                    Button("Choose File", systemImage: "folder") { isShowingFilePicker = true }
                } label: {
                    ProfileCoverBanner(
                        userID: session.userID,
                        coverPicture: profile?.coverPicture,
                        preview: state.selectedImage
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius))
                    .overlay {
                        if state.selectedImage == nil && profile?.coverPicture == nil {
                            Image(systemName: "plus")
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .menuIndicator(.hidden)
                .disabled(state.isUploading)
                .accessibilityIdentifier("cover-picker")
                .padding(.top, 20)

                Spacer()

                Button(action: submit) {
                    ButtonStateLabel("Save", state: buttonState)
                }
                .buttonStyle(.filled)
                .disabled(!state.canSubmitPhoto || !buttonState.isNormal)
                .accessibilityIdentifier("cover-save")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle("Cover")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .fullScreenCover(isPresented: $isShowingPhotoPicker) {
            ImagePickerWithEditor(
                onImagePicked: state.select,
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
        .task(id: state.uploadAttemptID) {
            guard state.hasPendingUpload else { return }
            await upload()
        }
    }

    private func submit() {
        state.beginUpload()
    }

    private func upload() async {
        buttonState = .loading
        do {
            try await state.uploadPhoto(
                with: SessionProfilePictureUploader(
                    session: session,
                    flipClient: container.flipClient,
                    slot: .cover
                )
            )

            buttonState = .success
            try? await Task.delay(milliseconds: 500)
            guard !Task.isCancelled else { return }

            state.releaseSelectedImage()
            router.popTopmost()

        } catch let error as ErrorBlob {
            buttonState = .normal
            guard !Task.isCancelled else { return }
            logger.info("Cover upload failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Cover upload failed", userFacing: true)
            dialog = .profilePictureFailed(error)

        } catch let error as ImageEncoderError {
            buttonState = .normal
            logger.error("Failed to encode the cover", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to encode the cover")
            dialog = .imageProcessingFailed

        } catch {
            buttonState = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set cover picture", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set cover picture")
            dialog = .error(
                title: "Couldn't Upload Your Cover",
                subtitle: "Try again"
            )
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            logger.info("Cover file import failed", metadata: ["error": "\(error)"])

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
                dialog = .error(
                    title: "Couldn't Open That File",
                    subtitle: "Try a different image"
                )
                return
            }

            state.select(image)
        }
    }
}
