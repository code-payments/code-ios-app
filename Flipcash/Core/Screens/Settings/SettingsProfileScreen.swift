//
//  SettingsProfileScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.settings-profile")

/// Edits an existing profile's name and photo independently. Deliberately not
/// the creation screens: those advance a two-step flow, this one saves in place.
struct SettingsProfileScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var displayName: String = ""
    @State private var isShowingPhotoPicker = false
    @State private var isSavingName = false
    @State private var isSavingPhoto = false
    @State private var avatar: UIImage?
    @State private var errorDialog: DialogItem?

    @State private var validator = DisplayNameValidator()

    private static let avatarSize: CGFloat = 120

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Button {
                    isShowingPhotoPicker = true
                } label: {
                    ZStack {
                        CircleImage(image: avatar, size: Self.avatarSize, plusSize: 32)

                        if isSavingPhoto {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: Self.avatarSize, height: Self.avatarSize)
                            ProgressView().progressViewStyle(.circular)
                        }
                    }
                }
                .disabled(isSavingPhoto)
                .padding(.top, 32)
                .accessibilityIdentifier("settings-profile-photo")

                TextField("Your Name", text: $displayName)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .textContentType(.name)
                    .disabled(isSavingName)
                    .padding(.top, 24)

                Spacer()

                Button(action: saveName) {
                    if isSavingName {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.filled)
                .disabled(!canSaveName)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
        .fullScreenCover(isPresented: $isShowingPhotoPicker) {
            ImagePickerWithEditor(
                onImagePicked: savePhoto,
                onDismiss: { isShowingPhotoPicker = false }
            )
            .ignoresSafeArea()
        }
        .task(id: profilePicture?.blobID) {
            displayName = sessionContainer.session.profile?.displayName ?? ""
            await loadAvatar()
        }
    }

    private var profilePicture: ProfilePicture? {
        sessionContainer.session.profile?.profilePicture
    }

    private var canSaveName: Bool {
        guard let validated = validator.validate(displayName), !isSavingName else { return false }
        return validated != sessionContainer.session.profile?.displayName
    }

    // MARK: - Saving -

    private func saveName() {
        guard let name = validator.validate(displayName), !isSavingName else { return }

        isSavingName = true
        Task {
            defer { isSavingName = false }

            do {
                try await container.flipClient.setDisplayName(
                    name,
                    owner: sessionContainer.session.ownerKeyPair
                )
                try await sessionContainer.session.updateProfile()

            } catch ErrorProfile.moderated(let category) {
                logger.info("Display name moderation denied", metadata: ["category": "\(category)"])
                errorDialog = .error(title: "This Name is Not Allowed", subtitle: "Try a different name")

            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to update display name", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to update display name")
                errorDialog = .error(title: "Couldn't Save Your Name", subtitle: "Try again")
            }
        }
    }

    private func savePhoto(_ image: UIImage) {
        isSavingPhoto = true
        Task {
            defer { isSavingPhoto = false }

            do {
                let compressed = await ImageCompressor.compress(
                    image,
                    maxDimension: ProfileCreationState.maxImageDimension
                )
                avatar = compressed

                let data = try await ImageEncoder.encodeForUpload(compressed, maxBytes: 2 * 1_024 * 1_024)
                let owner = sessionContainer.session.ownerKeyPair
                let blobID = try await container.flipClient.uploadBlob(data, mimeType: "image/jpeg", owner: owner)

                _ = try await container.flipClient.setProfilePicture(blobID: blobID, owner: owner)
                try await sessionContainer.session.updateProfile()

            } catch ErrorBlob.rejected(let reason) {
                logger.info("Profile picture rejected", metadata: ["reason": "\(reason)"])
                await loadAvatar()
                errorDialog = .profilePictureRejected(reason)

            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to update profile picture", metadata: ["error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Failed to update profile picture")
                await loadAvatar()
                errorDialog = .error(title: "Couldn't Upload Your Photo", subtitle: "Try again")
            }
        }
    }

    private func loadAvatar() async {
        guard let picture = profilePicture, let url = picture.thumbnailURL else { return }

        do {
            avatar = try await RemoteImageLoader.image(at: url, cacheKey: picture.blobID.description)
        } catch {
            guard !Task.isCancelled else { return }
            logger.info("Failed to load profile picture", metadata: ["error": "\(error)"])
        }
    }
}
