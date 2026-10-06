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

    /// Attaches the finalized blob to the profile slot this uploader targets.
    func attach(blobID: BlobID) async throws

    /// Re-reads the profile so the rest of the app sees the new picture.
    func refreshProfile() async throws
}

/// Which picture on the profile an upload replaces.
enum ProfilePictureSlot: Sendable {
    /// The round profile picture.
    case avatar
    /// The banner behind it.
    case cover
}

/// Uploads on behalf of the signed-in owner.
struct SessionProfilePictureUploader: ProfilePictureUploading {

    let session: Session
    let flipClient: FlipClient
    let slot: ProfilePictureSlot

    func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }

    func attach(blobID: BlobID) async throws {
        let owner = session.ownerKeyPair
        try await Self.attach(
            blobID,
            to: slot,
            setAvatar: { try await flipClient.setProfilePicture(blobID: $0, owner: owner) },
            // The `refreshProfile` that follows re-reads the cover, so the echo is dropped.
            setCover: { _ = try await flipClient.setCoverPicture(blobID: $0, owner: owner) }
        )
    }

    /// Routes `blobID` to the call for `slot`. Closures stand in for `FlipClient`, a concrete
    /// class with a live gRPC channel, so a test can observe the routing.
    static func attach(
        _ blobID: BlobID,
        to slot: ProfilePictureSlot,
        setAvatar: (BlobID) async throws -> Void,
        setCover: (BlobID) async throws -> Void
    ) async throws {
        switch slot {
        case .avatar: try await setAvatar(blobID)
        case .cover:  try await setCover(blobID)
        }
    }

    func refreshProfile() async throws {
        try await session.updateProfile()
    }
}
