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

// MARK: - Codable -

extension ProfilePicture {

    /// Only the blob survives being stored. Download URLs are signed and
    /// short-lived, so a persisted one is expired by the time it is read back —
    /// the blob is the durable handle, and the URLs come from the next fetch.
    private enum CodingKeys: String, CodingKey {
        case blobID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            blobID: try container.decode(BlobID.self, forKey: .blobID),
            thumbnailURL: nil,
            displayURL: nil,
            expiresAt: nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blobID, forKey: .blobID)
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

        let thumbnail = renditions.largest(role: .thumbnail) ?? original
        let display   = renditions.largest(role: .display)   ?? original

        self.init(
            blobID: BlobID(data: original.blobID.value),
            thumbnailURL: thumbnail.downloadURL,
            displayURL: display.downloadURL,
            expiresAt: thumbnail.downloadExpiry
        )
    }
}

private extension Array where Element == Flipcash_Blob_V1_Rendition {

    /// The highest-resolution rendition for `role`. The server derives several
    /// sizes per role and orders them arbitrarily.
    func largest(role: Flipcash_Blob_V1_Rendition.Role) -> Element? {
        filter { $0.role == role }.max { $0.pixelWidth < $1.pixelWidth }
    }
}

private extension Flipcash_Blob_V1_Rendition {

    var pixelWidth: UInt32 {
        hasBlob ? blob.image.width : 0
    }


    var downloadURL: URL? {
        guard hasBlob, blob.hasDownloadURL else { return nil }
        return URL(string: blob.downloadURL.url)
    }

    var downloadExpiry: Date? {
        guard hasBlob, blob.hasDownloadURL, blob.downloadURL.hasExpiresAt else { return nil }
        return blob.downloadURL.expiresAt.date
    }
}
