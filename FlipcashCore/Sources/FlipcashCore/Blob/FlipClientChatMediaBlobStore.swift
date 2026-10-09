//
//  FlipClientChatMediaBlobStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Stores chat photos for `owner` straight through a `FlipClient`, for a process with no session,
/// such as a share extension.
public struct FlipClientChatMediaBlobStore: ChatMediaBlobStoring {

    private let flipClient: FlipClient
    private let owner: KeyPair

    public init(flipClient: FlipClient, owner: KeyPair) {
        self.flipClient = flipClient
        self.owner = owner
    }

    public func uploadPolicy() async throws -> UploadPolicy {
        try await flipClient.uploadPolicy(owner: owner)
    }

    public func storeBlob(_ data: Data, mimeType: String, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> BlobID {
        try await flipClient.storeBlob(data, mimeType: mimeType, owner: owner, onProgress: onProgress)
    }

    public func storeEncryptedBlob(_ image: Data, seal: ChatSeal, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> EncryptedBlobUpload {
        try await flipClient.storeEncryptedBlob(image, seal: seal, owner: owner, onProgress: onProgress)
    }

    public func awaitBlobFinalization(blobID: BlobID) async throws {
        try await flipClient.awaitBlobFinalization(blobID: blobID, owner: owner)
    }
}
