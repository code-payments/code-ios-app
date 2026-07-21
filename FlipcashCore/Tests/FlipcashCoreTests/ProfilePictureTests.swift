//
//  ProfilePictureTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("Profile Picture Tests")
struct ProfilePictureTests {

    /// The server derives several sizes per role and orders them arbitrarily, so
    /// the avatar has to be chosen by resolution rather than by position.
    @Test("Picks the highest-resolution thumbnail regardless of order")
    func picksTheLargestThumbnail() throws {
        let media = Self.media([
            (role: .original,  id: 1, width: 1600),
            (role: .thumbnail, id: 2, width: 64),
            (role: .thumbnail, id: 3, width: 320),
            (role: .thumbnail, id: 4, width: 128),
        ])

        let picture = try #require(ProfilePicture(media))

        #expect(picture.blobID == Self.blobID(1))
        #expect(picture.thumbnailBlobID == Self.blobID(3))
    }

    /// A just-attached picture can come back before its renditions are derived.
    @Test("Falls back to the original when no thumbnail was derived")
    func fallsBackToTheOriginal() throws {
        let media = Self.media([(role: .original, id: 1, width: 1600)])

        let picture = try #require(ProfilePicture(media))

        #expect(picture.thumbnailBlobID == picture.blobID)
    }

    /// Renditions carry no metadata until the blob is resolved, so the width
    /// comparison has to tolerate its absence rather than trap.
    @Test("Picks a thumbnail even when no rendition carries dimensions")
    func picksAThumbnailWithoutMetadata() throws {
        var original  = Flipcash_Blob_V1_Rendition()
        original.role = .original
        original.blobID = .with { $0.value = Self.blobID(1).data }

        var thumbnail  = Flipcash_Blob_V1_Rendition()
        thumbnail.role = .thumbnail
        thumbnail.blobID = .with { $0.value = Self.blobID(2).data }

        let media = Flipcash_Blob_V1_Media.with { $0.renditions = [original, thumbnail] }

        let picture = try #require(ProfilePicture(media))

        #expect(picture.thumbnailBlobID == Self.blobID(2))
    }

    /// The original is the durable identity; without it there is nothing to
    /// re-derive from, so the media is not a usable picture.
    @Test("Returns nil when the media carries no original")
    func returnsNilWithoutAnOriginal() {
        let media = Self.media([(role: .thumbnail, id: 2, width: 320)])

        #expect(ProfilePicture(media) == nil)
    }

    @Test("Returns nil for empty media")
    func returnsNilForEmptyMedia() {
        #expect(ProfilePicture(Flipcash_Blob_V1_Media()) == nil)
    }

    // MARK: - Fixtures -

    private static func blobID(_ seed: UInt8) -> BlobID {
        BlobID(data: Data(repeating: seed, count: 16))
    }

    private static func media(
        _ renditions: [(role: Flipcash_Blob_V1_Rendition.Role, id: UInt8, width: UInt32)]
    ) -> Flipcash_Blob_V1_Media {
        Flipcash_Blob_V1_Media.with { media in
            media.renditions = renditions.map { rendition in
                Flipcash_Blob_V1_Rendition.with {
                    $0.role   = rendition.role
                    $0.blobID = .with { $0.value = blobID(rendition.id).data }
                    $0.blob   = .with { metadata in
                        metadata.mimeType = "image/jpeg"
                        metadata.image = .with { $0.width = rendition.width }
                    }
                }
            }
        }
    }
}
