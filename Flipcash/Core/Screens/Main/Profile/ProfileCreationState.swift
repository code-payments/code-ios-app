//
//  ProfileCreationState.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.profile-creation")

/// Drives profile creation across the name and photo screens.
///
/// Owned by the Tips sheet root so the entered name survives a push, and so a
/// running upload is not torn down when a screen is popped.
@Observable
final class ProfileCreationState {

    var displayName: String = ""

    var selectedImage: UIImage? {
        didSet {
            guard selectedImage !== oldValue else { return }
            // A different photo needs its own blob: rejection is terminal and a
            // reserved upload is signed against the previous byte count.
            reservedBlobID = nil
        }
    }

    /// Bumped to start an upload attempt. The photo screen keys its `task` on
    /// this, so SwiftUI owns cancellation and "Try Again" is a re-run.
    private(set) var uploadAttemptID: Int = 0

    private(set) var isUploading = false

    /// Set once the bytes are stored. A timed-out attempt resumes against this
    /// rather than reserving a second upload.
    private(set) var reservedBlobID: BlobID?

    @ObservationIgnored private let validator = DisplayNameValidator()

    /// The name accepted by `SetDisplayName`, or nil while the input is invalid.
    /// This exact string is what gets submitted.
    var validatedDisplayName: String? {
        validator.validate(displayName)
    }

    var isDisplayNameValid: Bool {
        validatedDisplayName != nil
    }

    var remainingCharacters: Int {
        validator.remaining(in: displayName)
    }

    var canSubmitPhoto: Bool {
        selectedImage != nil && !isUploading
    }

    func beginUpload() {
        uploadAttemptID += 1
    }

    // MARK: - Upload -

    /// Uploads the selected photo and attaches it to the profile.
    ///
    /// Resumes a previous attempt when its bytes are already stored.
    func uploadPhoto(session: Session, flipClient: FlipClient) async throws {
        guard let image = selectedImage else { return }

        isUploading = true
        defer { isUploading = false }

        let owner = session.ownerKeyPair

        let blobID: BlobID
        if let reservedBlobID {
            logger.info("Resuming profile picture finalization", metadata: ["blobId": "\(reservedBlobID)"])
            try await flipClient.awaitBlobFinalization(blobID: reservedBlobID, owner: owner)
            blobID = reservedBlobID
        } else {
            // Encode before reserving: the signed policy pins the byte count, so
            // the bytes may not change after `InitiateExternalUpload`.
            let data = try await ImageEncoder.encodeForUpload(image, maxBytes: Self.maxUploadBytes)
            blobID = try await flipClient.uploadBlob(data, mimeType: "image/jpeg", owner: owner)
            reservedBlobID = blobID
        }

        _ = try await flipClient.setProfilePicture(blobID: blobID, owner: owner)
        try await session.updateProfile()
    }

    /// The server accepts 8 MiB, but its largest derived rendition is 1600px —
    /// a bigger original buys nothing.
    private static let maxUploadBytes = 2 * 1_024 * 1_024
    static let maxImageDimension: CGFloat = 1600
}
