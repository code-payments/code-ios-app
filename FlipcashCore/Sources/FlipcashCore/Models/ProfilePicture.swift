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

/// A user's profile picture, as the blobs backing its renditions.
///
/// Carries no download URL by design: those are signed, short-lived, and
/// re-minted on every fetch, so a stored one is expired before it is read back.
/// A caller that needs the bytes mints a URL from these ids.
public struct ProfilePicture: Codable, Hashable, Sendable {

    /// The blob holding the full-quality original the user uploaded.
    public let blobID: BlobID

    /// The blob holding the avatar-sized rendition.
    public let thumbnailBlobID: BlobID

    /// The thumbnail rendition's BlurHash, a compact blurred preview shown while
    /// the bytes download. Nil when the server carried none.
    public let thumbnailBlurhash: String?

    public init(blobID: BlobID, thumbnailBlobID: BlobID, thumbnailBlurhash: String? = nil) {
        self.blobID            = blobID
        self.thumbnailBlobID   = thumbnailBlobID
        self.thumbnailBlurhash = thumbnailBlurhash
    }
}

// MARK: - Codable -

extension ProfilePicture {

    /// Falls back to the original when a stored row predates `thumbnailBlobID`,
    /// so a profile written by an earlier build still decodes. Rows persist as
    /// one JSON blob, and a throw here empties the whole profile.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let blobID = try container.decode(BlobID.self, forKey: .blobID)

        self.init(
            blobID: blobID,
            thumbnailBlobID: try container.decodeIfPresent(BlobID.self, forKey: .thumbnailBlobID) ?? blobID,
            thumbnailBlurhash: try container.decodeIfPresent(String.self, forKey: .thumbnailBlurhash)
        )
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

        // Falls back to the original so a media whose thumbnail has not been
        // derived yet still resolves to something fetchable.
        let thumbnail = renditions.largest(role: .thumbnail) ?? original

        self.init(
            blobID: BlobID(data: original.blobID.value),
            thumbnailBlobID: BlobID(data: thumbnail.blobID.value),
            thumbnailBlurhash: thumbnail.blurhash
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

    /// The rendition's BlurHash preview, or nil when the blob carries none.
    var blurhash: String? {
        guard hasBlob, !blob.image.blurhash.isEmpty else { return nil }
        return blob.image.blurhash
    }
}
