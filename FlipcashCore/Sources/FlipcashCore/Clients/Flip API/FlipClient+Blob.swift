//
//  FlipClient+Blob.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Stores `data` and returns its blob, before the server has finalized it.
    ///
    /// Pair with `awaitBlobFinalization(blobID:owner:)`: holding the blob from
    /// the moment the bytes land is what lets a timed-out wait resume rather
    /// than upload a second copy.
    public func storeBlob(_ data: Data, mimeType: String, owner: KeyPair) async throws -> BlobID {
        try await blobUploader.store(data, mimeType: mimeType, owner: owner)
    }

    /// Returns a freshly minted download URL for a blob the caller owns.
    public func blobDownloadURL(blobID: BlobID, owner: KeyPair) async throws -> URL? {
        try await blobService.downloadURL(blobID: blobID, owner: owner)
    }

    /// Waits for an already-uploaded blob to finish finalizing.
    ///
    /// Resumes an attempt whose polling timed out, without re-uploading.
    public func awaitBlobFinalization(blobID: BlobID, owner: KeyPair) async throws {
        try await blobUploader.awaitFinalization(blobID: blobID, owner: owner)
    }
}
