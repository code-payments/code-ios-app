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

    /// Where a saved photo leads.
    enum Completion {
        /// Profile setup: on to the tip card the profile was made for.
        case tipcard
        /// A lone edit: back to the screen that opened this one.
        case back
    }

    var completion: Completion = .tipcard

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ProfileCreationState.self) private var state

    @State private var isShowingPhotoPicker = false
    @State private var isShowingFilePicker = false
    @State private var errorDialog: DialogItem?

    /// Drives the submit button: spinner while uploading, then the checkmark the
    /// rest of the app shows on a completed action.
    @State private var buttonState: ButtonState = .normal

    /// The picture already on the profile, so a lone edit opens on what it is
    /// about to replace rather than on an empty circle. Drawn but never
    /// submitted — Save stays shut until a new photo is picked.
    @State private var currentPhoto: UIImage?

    private static let avatarSize: CGFloat = 158
    private static let plusSize: CGFloat = 64

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                if completion == .tipcard {
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
                }

                Spacer()

                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { isShowingPhotoPicker = true }
                    Button("Choose File", systemImage: "folder") { isShowingFilePicker = true }
                } label: {
                    CircleImage(
                        image: state.selectedImage ?? currentPhoto,
                        size: Self.avatarSize,
                        plusSize: Self.plusSize
                    )
                }
                .menuIndicator(.hidden)
                .disabled(state.isUploading)
                .accessibilityIdentifier("profile-photo-picker")

                if let name = state.validatedDisplayName {
                    Text(name)
                        .font(.appDisplayCompact)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .padding(.top, 21)
                }

                Spacer()

                Button(action: state.beginUpload) {
                    ButtonStateLabel(completion == .tipcard ? "Next" : "Save", state: buttonState)
                }
                .buttonStyle(.filled)
                // The checkmark hold keeps the photo selected, so the button
                // needs the state to stay shut against a second submission.
                .disabled(!state.canSubmitPhoto || !buttonState.isNormal)
                .accessibilityIdentifier("profile-photo-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(completion == .tipcard ? "" : "Set Profile Picture")
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
        // Keyed on the blob so a picture that changes underneath — including the
        // one this screen just uploaded — is what the circle ends up drawing.
        .task(id: profilePicture?.thumbnailBlobID) {
            currentPhoto = await ProfilePictureLoader.thumbnail(
                for: profilePicture,
                using: container.flipClient,
                owner: sessionContainer.session.ownerKeyPair
            )
        }
    }

    private var profilePicture: ProfilePicture? {
        sessionContainer.session.profile?.profilePicture
    }

    private func upload() async {
        buttonState = .loading
        do {
            try await state.uploadPhoto(
                with: SessionProfilePictureUploader(
                    session: sessionContainer.session,
                    flipClient: container.flipClient
                )
            )

            buttonState = .success
            // Same beat onboarding holds its checkmark for, so the confirmation
            // is seen before the screen changes.
            try? await Task.delay(milliseconds: 500)

            // Held as the current picture first: releasing the selection alone
            // would drop the circle back to whatever was downloaded before this
            // upload, for as long as the pop takes.
            currentPhoto = state.selectedImage
            // Released only now: dropping it any earlier empties the avatar back
            // to its placeholder while the checkmark is still up.
            state.releaseSelectedImage()

            guard !Task.isCancelled else { return }

            switch completion {
            case .tipcard:
                // Creation lands on the tipcard — the thing the profile was made
                // for — with the conversation list beneath it as the Tips root.
                router.popToRoot(on: .tips)
                router.push(.tipcard)
            case .back:
                router.popTopmost()
            }

        } catch let error as ErrorBlob {
            buttonState = .normal
            guard !Task.isCancelled else { return }
            logger.info("Profile picture upload failed", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Profile picture upload failed")
            errorDialog = .profilePictureFailed(error)

        } catch let error as ImageEncoderError {
            buttonState = .normal
            logger.error("Failed to encode the profile picture", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to encode the profile picture")
            errorDialog = .imageProcessingFailed

        } catch {
            buttonState = .normal
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
