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

    private(set) var selectedImage: UIImage? {
        didSet {
            guard selectedImage !== oldValue else { return }
            // A different photo needs its own blob: rejection is terminal and a
            // reserved upload is signed against the previous byte count.
            reservedBlobID = nil
        }
    }

    @ObservationIgnored private var compressTask: Task<Void, Never>?

    /// Bumped to start an upload attempt. The photo screen keys its `task` on
    /// this, so SwiftUI owns cancellation and "Try Again" is a re-run.
    private(set) var uploadAttemptID: Int = 0

    /// Whether the current attempt still needs to run. Cleared when it settles,
    /// so returning to the screen doesn't re-submit on its own — the state
    /// outlives the screen and the counter never resets.
    private(set) var hasPendingUpload = false

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

    /// Compresses `image` and makes it the selection, replacing any earlier pick
    /// still compressing so a slow one can't land last and win.
    func select(_ image: UIImage) {
        compressTask?.cancel()
        compressTask = Task {
            let compressed = await ImageCompressor.compress(image, maxDimension: Self.maxImageDimension)
            guard !Task.isCancelled else { return }
            selectedImage = compressed
        }
    }

    func beginUpload() {
        // A pick still compressing would land mid-upload and replace the bytes
        // the reservation is signed against; what is on screen is what uploads.
        compressTask?.cancel()
        hasPendingUpload = true
        uploadAttemptID += 1
    }

    // MARK: - Upload -

    /// Uploads the selected photo and attaches it to the profile.
    ///
    /// Resumes a previous attempt when its bytes are already stored.
    func uploadPhoto(with uploader: some ProfilePictureUploading) async throws {
        guard let image = selectedImage else {
            throw ErrorBlob.notFound
        }

        isUploading = true
        defer {
            isUploading = false
            hasPendingUpload = false
        }

        if let reservedBlobID {
            logger.info("Resuming profile picture finalization", metadata: ["blobId": "\(reservedBlobID)"])
        } else {
            // Encode before storing: the reservation signs the byte count, so the
            // bytes may not change afterwards.
            let data = try await ImageEncoder.encodeForUpload(image, maxBytes: Self.maxUploadBytes)
            // Held from the moment the bytes land, so a timed-out wait resumes
            // this blob rather than storing a second copy.
            reservedBlobID = try await uploader.storeBlob(data, mimeType: "image/jpeg")
        }

        guard let blobID = reservedBlobID else { return }

        do {
            try await uploader.awaitBlobFinalization(blobID: blobID)
        } catch ErrorBlob.rejected(let reason) {
            reservedBlobID = nil
            throw ErrorBlob.rejected(reason)
        }

        try await uploader.setProfilePicture(blobID: blobID)
        try await uploader.refreshProfile()

        // The sheet root outlives this flow, so the bitmap would sit resident
        // until the sheet closes.
        selectedImage = nil
    }

    private static let maxUploadBytes = 2 * 1_024 * 1_024

    /// The server's largest derived rendition, so a bigger original buys nothing.
    static let maxImageDimension: CGFloat = 1600
}
