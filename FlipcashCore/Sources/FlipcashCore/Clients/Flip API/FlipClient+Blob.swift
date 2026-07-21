//
//  FlipClient+Blob.swift
//  FlipcashCore
//

import Foundation

extension FlipClient {

    /// Uploads `data` to blob storage and returns its blob once the server has
    /// finalized it.
    public func uploadBlob(_ data: Data, mimeType: String, owner: KeyPair) async throws -> BlobID {
        try await blobUploader.upload(data, mimeType: mimeType, owner: owner)
    }

    /// Waits for an already-uploaded blob to finish finalizing.
    ///
    /// Resumes an attempt whose polling timed out, without re-uploading.
    public func awaitBlobFinalization(blobID: BlobID, owner: KeyPair) async throws {
        try await blobUploader.awaitFinalization(blobID: blobID, owner: owner)
    }
}
