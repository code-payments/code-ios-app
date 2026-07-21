//
//  ProfileCreationState.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

private let logger = Logger(label: "flipcash.profile-creation")

/// Drives profile creation across the name and photo screens.
///
/// Owned by the Tips sheet root so the name entered on one screen survives the
/// push to the next, and so a resumable upload outlives the screen that
/// started it.
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

        if let reservedBlobID {
            logger.info("Resuming profile picture finalization", metadata: ["blobId": "\(reservedBlobID)"])
        } else {
            // Encode before storing: the reservation signs the byte count, so the
            // bytes may not change afterwards.
            let data = try await ImageEncoder.encodeForUpload(image, maxBytes: Self.maxUploadBytes)
            // Held from the moment the bytes land, so a timed-out wait resumes
            // this blob rather than storing a second copy.
            reservedBlobID = try await flipClient.storeBlob(data, mimeType: "image/jpeg", owner: owner)
        }

        guard let blobID = reservedBlobID else { return }

        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: owner)
        _ = try await flipClient.setProfilePicture(blobID: blobID, owner: owner)
        try await session.updateProfile()

        // The sheet root outlives this flow, so the bitmap would sit resident
        // until the sheet closes.
        selectedImage = nil
    }

    private static let maxUploadBytes = 2 * 1_024 * 1_024

    /// The server's largest derived rendition, so a bigger original buys nothing.
    static let maxImageDimension: CGFloat = 1600
}
