//
//  ProfilePictureUploading.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The remote half of attaching a profile picture, in the order the flow calls it.
///
/// The owner is bound by the conformer, so the flow never handles keys.
protocol ProfilePictureUploading {

    /// Stores `data` and returns its blob, before the server has finalized it.
    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID

    /// Returns once the blob is servable, throwing `ErrorBlob.rejected` when it
    /// is refused and `ErrorBlob.timedOut` when it is still processing.
    func awaitBlobFinalization(blobID: BlobID) async throws

    /// Attaches the finalized blob to the caller's profile.
    func setProfilePicture(blobID: BlobID) async throws

    /// Re-reads the profile so the rest of the app sees the new picture.
    func refreshProfile() async throws
}

/// Uploads on behalf of the signed-in owner.
struct SessionProfilePictureUploader: ProfilePictureUploading {

    let session: Session
    let flipClient: FlipClient

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }

    func setProfilePicture(blobID: BlobID) async throws {
        try await flipClient.setProfilePicture(blobID: blobID, owner: session.ownerKeyPair)
    }

    func refreshProfile() async throws {
        try await session.updateProfile()
    }
}
