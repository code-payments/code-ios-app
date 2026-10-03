//
//  MockChatMediaBlobStore.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
@testable import FlipcashCore
@testable import Flipcash

/// Records each blob call and lets a test choose how storing and finalization end.
@MainActor
final class MockChatMediaBlobStore: ChatMediaBlobStoring {

    static let blobID = BlobID(data: Data(repeating: 4, count: 16))

    var policy: UploadPolicy
    /// Consumed one per `storeBlob` call; once empty, every call succeeds.
    var storeResults: [Result<BlobID, Error>] = []
    var finalization: Result<Void, Error> = .success(())
    var onStore: (() -> Void)?
    /// Reported through each store call's `onProgress` before it ends.
    var progressReports: [BlobUploadProgress] = []

    private(set) var storeAttempts = 0
    private(set) var storedData: [Data] = []
    private(set) var storedMimeTypes: [String] = []
    private(set) var finalizedBlobIDs: [BlobID] = []
    /// The plaintext images `storeEncryptedBlob` was handed, with the chat each was sealed for.
    private(set) var encryptedStores: [(image: Data, conversationID: ConversationID)] = []

    init(policy: UploadPolicy = UploadPolicy(version: "v1", ttl: nil, constraints: [
        .init(pattern: "image/*", maxSizeBytes: 5_000_000, image: .init(maxWidth: 2048, maxHeight: 2048, maxPixels: 0)),
    ])) {
        self.policy = policy
    }

    func uploadPolicy() async throws -> UploadPolicy {
        policy
    }

    func storeBlob(_ data: Data, mimeType: String, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> BlobID {
        storeAttempts += 1
        progressReports.forEach(onProgress)
        onStore?()
        let result = storeResults.isEmpty ? .success(Self.blobID) : storeResults.removeFirst()
        let blobID = try result.get()
        storedData.append(data)
        storedMimeTypes.append(mimeType)
        return blobID
    }

    func storeEncryptedBlob(_ image: Data, seal: ChatSeal, onProgress: @escaping @Sendable (BlobUploadProgress) -> Void) async throws -> EncryptedBlobUpload {
        storeAttempts += 1
        progressReports.forEach(onProgress)
        onStore?()
        let result = storeResults.isEmpty ? .success(Self.blobID) : storeResults.removeFirst()
        let blobID = try result.get()
        encryptedStores.append((image, seal.conversationID))
        return EncryptedBlobUpload(blobID: blobID, plaintextSize: image.count)
    }

    func awaitBlobFinalization(blobID: BlobID) async throws {
        try finalization.get()
        finalizedBlobIDs.append(blobID)
    }
}
