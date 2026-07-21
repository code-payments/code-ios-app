//
//  ProfilePicture.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// A handle to the blob backing a profile picture.
///
/// Sixteen opaque bytes, minted by `InitiateExternalUpload`.
public typealias BlobID = ID

/// A user's profile picture: the durable blob handle plus the renditions the
/// server derived from it.
public struct ProfilePicture: Codable, Equatable, Sendable {

    /// The original rendition's blob. Stable across fetches — use it as the
    /// image cache key, never the URL.
    public let blobID: BlobID

    /// Signed URL for the avatar-sized rendition, expiring at `expiresAt`.
    public let thumbnailURL: URL?

    /// Signed URL for the full-size rendition, expiring at `expiresAt`.
    public let displayURL: URL?

    /// When the signed URLs stop resolving.
    public let expiresAt: Date?

    public init(blobID: BlobID, thumbnailURL: URL?, displayURL: URL?, expiresAt: Date?) {
        self.blobID       = blobID
        self.thumbnailURL = thumbnailURL
        self.displayURL   = displayURL
        self.expiresAt    = expiresAt
    }
}

// MARK: - Proto -

extension ProfilePicture {

    /// Returns the picture described by `proto`, or `nil` when it carries no
    /// original rendition.
    init?(_ proto: Flipcash_Blob_V1_Media) {
        let renditions = proto.renditions

        guard let original = renditions.first(where: { $0.role == .original }) else {
            return nil
        }

        let thumbnail = renditions.first { $0.role == .thumbnail } ?? original
        let display   = renditions.first { $0.role == .display }   ?? original

        self.init(
            blobID: BlobID(data: original.blobID.value),
            thumbnailURL: thumbnail.downloadURL,
            displayURL: display.downloadURL,
            expiresAt: thumbnail.downloadExpiry
        )
    }
}

private extension Flipcash_Blob_V1_Rendition {

    var downloadURL: URL? {
        guard hasBlob, blob.hasDownloadURL else { return nil }
        return URL(string: blob.downloadURL.url)
    }

    var downloadExpiry: Date? {
        guard hasBlob, blob.hasDownloadURL, blob.downloadURL.hasExpiresAt else { return nil }
        return blob.downloadURL.expiresAt.date
    }
}
