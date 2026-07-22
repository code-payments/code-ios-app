//
//  ProfilePhotoScreen.swift
//  Flipcash
//

import SwiftUI
import UniformTypeIdentifiers
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.profile-photo")

struct ProfilePhotoScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ProfileCreationState.self) private var state

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var errorDialog: DialogItem?

    private static let avatarSize: CGFloat = 150

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Text("Upload Your Photo")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                Text("This photo will be shown when receiving tips")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)

                Spacer()

                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isShowingPhotoPicker = true }
                    Button("Choose File", systemImage: "folder") { isShowingFilePicker = true }
                } label: {
                    CircleImage(image: state.selectedImage, size: Self.avatarSize, plusSize: 40)
                }
                .menuIndicator(.hidden)
                .disabled(state.isUploading)
                .accessibilityIdentifier("profile-photo-picker")

                if let name = state.validatedDisplayName {
                    Text(name)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .padding(.top, 16)
                }

                Spacer()

                Button(action: state.beginUpload) {
                    if state.isUploading {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.filled)
                .disabled(!state.canSubmitPhoto)
                .accessibilityIdentifier("profile-photo-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
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
        // Keyed on the attempt so a retry re-runs it, and so SwiftUI cancels the
        // poll when this screen goes away.
        .task(id: state.uploadAttemptID) {
            guard state.hasPendingUpload else { return }
            await upload()
        }
    }

    private func upload() async {
        do {
            try await state.uploadPhoto(
                with: SessionProfilePictureUploader(
                    session: sessionContainer.session,
                    flipClient: container.flipClient
                )
            )
            // Creation lands on the tipcard — the thing the profile was made
            // for — with the conversation list beneath it as the Tips root.
            router.popToRoot(on: .tips)
            router.push(.tipcard)

        } catch let error as ErrorBlob {
            guard !Task.isCancelled else { return }
            logger.info("Profile picture upload failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Profile picture upload failed")
            errorDialog = .profilePictureFailed(error)

        } catch let error as ImageEncoderError {
            logger.error("Failed to encode the profile picture", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to encode the profile picture")
            errorDialog = .imageProcessingFailed

        } catch {
            guard !Task.isCancelled else { return }
            logger.error("Failed to set profile picture", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set profile picture")
            errorDialog = .error(
                title: "Couldn't Upload Your Photo",
                subtitle: "Try again"
            )
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            logger.info("Photo file import failed", metadata: ["error": "\(error)"])
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
                errorDialog = .error(
                    title: "Couldn't Open That File",
                    subtitle: "Try a different image"
                )
                return
            }

            state.select(image)
        }
    }
}
