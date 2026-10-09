//
//  SessionChatMediaBlobStore.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Stores chat photos on behalf of the signed-in owner.
struct SessionChatMediaBlobStore: ChatMediaBlobStoring {

    let session: Session
    let flipClient: FlipClient

    func uploadPolicy() async throws -> UploadPolicy {
        try await flipClient.uploadPolicy(owner: session.ownerKeyPair)
    }

    func storeBlob(_ data: Data, mimeType: String, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: session.ownerKeyPair, onProgress: onProgress)
    }

    func storeEncryptedBlob(_ image: Data, seal: ChatSeal, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> EncryptedBlobUpload {
        try await flipClient.storeEncryptedBlob(image, seal: seal, owner: session.ownerKeyPair, onProgress: onProgress)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: session.ownerKeyPair)
    }
}
