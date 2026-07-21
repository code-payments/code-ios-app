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
    @State private var compressTask: Task<Void, Never>?

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
                onImagePicked: setSelectedImage,
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
            guard state.uploadAttemptID > 0 else { return }
            await upload()
        }
    }

    private func upload() async {
        do {
            try await state.uploadPhoto(
                session: sessionContainer.session,
                flipClient: container.flipClient
            )
            // The Tips root renders the tipcard once the profile is complete.
            router.popToRoot(on: .tips)

        } catch ErrorBlob.rejected(let reason) {
            logger.info("Profile picture rejected", metadata: ["reason": "\(reason)"])
            errorDialog = .profilePictureRejected(reason)

        } catch ErrorBlob.timedOut {
            logger.info("Profile picture upload timed out")
            errorDialog = .error(
                title: "Couldn't Upload Your Photo",
                subtitle: "Try again"
            )

        } catch is ImageEncoderError {
            errorDialog = .error(
                title: "Couldn't Process Image",
                subtitle: "Try a smaller or simpler image"
            )

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

    private func setSelectedImage(_ image: UIImage) {
        compressTask?.cancel()
        compressTask = Task {
            let compressed = await ImageCompressor.compress(
                image,
                maxDimension: ProfileCreationState.maxImageDimension
            )
            guard !Task.isCancelled else { return }
            state.selectedImage = compressed
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        Task {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value

            guard let data, let image = UIImage(data: data) else {
                errorDialog = .error(
                    title: "Couldn't Open That File",
                    subtitle: "Try a different image"
                )
                return
            }

            setSelectedImage(image)
        }
    }
}
