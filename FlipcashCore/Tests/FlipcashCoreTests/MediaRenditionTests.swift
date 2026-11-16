//
//  MediaRenditionTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

/// Ports of Android's `MediaItemTest` (`renditionForSize` and the DISPLAY-capped role ladder it
/// degrades to) and `QuoteThumbnailRenditionTest`, case for case, built from the proto the server
/// sends so that "still uploading" runs through the same mapping a real message does.
@Suite("Media rendition selection")
struct MediaRenditionTests {

    private typealias Role = Flipcash_Blob_V1_Rendition.Role

    /// A rendition with image dimensions, `longestSide` wide and half as tall, or with no blob when
    /// it is still uploading.
    private func sized(_ role: Role, _ longestSide: Int, available: Bool = true, id: UInt8) -> Flipcash_Blob_V1_Rendition {
        .with {
            $0.role = role
            $0.blobID = .with { $0.value = Data(repeating: id, count: 16) }
            if available {
                $0.blob.sizeBytes = 1
                $0.blob.image.width = UInt32(longestSide)
                $0.blob.image.height = UInt32(longestSide / 2)
                $0.blob.image.blurhash = "abc"
            }
        }
    }

    /// A rendition whose blob carries no image dimensions, or no blob when it is still uploading.
    private func unsized(_ role: Role, available: Bool = true, id: UInt8) -> Flipcash_Blob_V1_Rendition {
        .with {
            $0.role = role
            $0.blobID = .with { $0.value = Data(repeating: id, count: 16) }
            if available { $0.blob.sizeBytes = 1 }
        }
    }

    private func attachment(_ renditions: Flipcash_Blob_V1_Rendition...) throws -> MediaAttachment {
        try #require(MediaAttachment(Flipcash_Blob_V1_Media.with { $0.renditions = renditions }))
    }

    private func blobID(_ id: UInt8) -> BlobID { BlobID(data: Data(repeating: id, count: 16)) }

    /// The server's rendition spec: three thumbnails and two display sizes, shuffled so selection
    /// can't lean on list order.
    private func sizedMedia() throws -> MediaAttachment {
        try attachment(
            sized(.thumbnail, 320, id: 1),
            sized(.display, 1600, id: 2),
            sized(.thumbnail, 32, id: 3),
            sized(.display, 800, id: 4),
            sized(.thumbnail, 160, id: 5),
            sized(.original, 4000, id: 6)
        )
    }

    private func derived(_ media: MediaAttachment, _ target: Int) -> MediaRendition? {
        MediaRendition.derived(forPixelSize: target, in: media.renditions)
    }

    // MARK: renditionForSize

    @Test("Picks the smallest rendition at least as large as the target")
    func smallestCovering() throws {
        let media = try sizedMedia()
        #expect(derived(media, 1)?.longestSide == 32)
        #expect(derived(media, 96)?.longestSide == 160)
        #expect(derived(media, 160)?.longestSide == 160)
        #expect(derived(media, 161)?.longestSide == 320)
        #expect(derived(media, 500)?.longestSide == 800)
    }

    @Test("Falls back to the largest derived rendition when the target exceeds all; the ORIGINAL is excluded")
    func largestWhenNoneCovers() throws {
        let media = try sizedMedia()
        #expect(derived(media, 9000)?.longestSide == 1600)
        #expect(media.rendition(forPixelSize: 9000)?.role == .display)
    }

    @Test("With the ORIGINAL the only sized rendition, there is no derived pick and the photo loads its ORIGINAL")
    func originalOnlyWhenSoleSized() throws {
        let media = try attachment(sized(.original, 4000, id: 6))
        #expect(derived(media, 100) == nil)
        #expect(media.rendition(forPixelSize: 100) == MediaRendition(role: .original, blobID: blobID(6), width: 4000, height: 2000))
    }

    @Test("Skips renditions still uploading")
    func skipsUploading() throws {
        let media = try attachment(
            sized(.original, 4000, id: 6),
            sized(.thumbnail, 160, available: false, id: 1),
            sized(.thumbnail, 320, id: 2)
        )
        #expect(derived(media, 96)?.longestSide == 320)
        #expect(derived(media, 96)?.blobID == blobID(2))
    }

    @Test("Degrades to the role ladder when no derived rendition carries dimensions")
    func roleLadderWithoutDimensions() throws {
        let media = try attachment(
            sized(.original, 4000, id: 6),
            unsized(.display, id: 1),
            unsized(.thumbnail, id: 2)
        )
        #expect(derived(media, 100)?.role == .display)
        #expect(derived(media, 100)?.blobID == blobID(1))
    }

    // MARK: Role ladder, from DISPLAY down

    @Test("The ladder returns DISPLAY when it is available")
    func ladderPrefersDisplay() throws {
        let media = try attachment(
            unsized(.original, id: 6),
            unsized(.display, id: 1),
            unsized(.thumbnail, id: 2)
        )
        #expect(derived(media, 100)?.blobID == blobID(1))
    }

    @Test("The ladder skips a DISPLAY whose blob is not available yet and takes THUMBNAIL")
    func ladderSkipsUnavailableDisplay() throws {
        let media = try attachment(
            unsized(.original, id: 6),
            unsized(.display, available: false, id: 1),
            unsized(.thumbnail, id: 2)
        )
        #expect(derived(media, 100)?.role == .thumbnail)
    }

    @Test("The ladder never climbs to the ORIGINAL")
    func ladderNeverUpgrades() throws {
        let media = try attachment(unsized(.original, id: 6))
        #expect(derived(media, 100) == nil)
    }

    @Test("Nothing derived is available: no derived pick, and the photo loads its ORIGINAL")
    func nothingAvailable() throws {
        let media = try attachment(sized(.original, 4000, id: 6), unsized(.thumbnail, available: false, id: 1))
        #expect(media.renditions.isEmpty)
        #expect(derived(media, 100) == nil)
        #expect(media.rendition(forPixelSize: 100)?.role == .original)
    }

    // MARK: Additions (not in Android's suite)

    @Test("Equal covering sizes resolve to the first in list order, as Kotlin's stable sort does")
    func tieOnCoveringPicksFirst() throws {
        let media = try attachment(sized(.original, 4000, id: 6), sized(.display, 800, id: 1), sized(.display, 800, id: 2))
        #expect(derived(media, 500)?.blobID == blobID(1))
    }

    @Test("Equal largest sizes resolve to the last in list order, as Kotlin's `last()` does")
    func tieOnLargestPicksLast() throws {
        let media = try attachment(sized(.original, 4000, id: 6), sized(.display, 800, id: 1), sized(.display, 800, id: 2))
        #expect(derived(media, 9000)?.blobID == blobID(2))
    }

    @Test("A rendition of a role this build does not know still counts as a sized candidate, as on Android")
    func unknownRoleIsSized() throws {
        let media = try attachment(sized(.original, 4000, id: 6), sized(.UNRECOGNIZED(9), 200, id: 1), sized(.display, 800, id: 2))
        #expect(derived(media, 100)?.role == .unknown)
        #expect(derived(media, 100)?.blobID == blobID(1))
    }

    @Test("Mapping keeps each derived rendition's blob id, role and dimensions, in the server's order")
    func mappingKeepsDerived() throws {
        let media = try sizedMedia()
        #expect(media.blobID == blobID(6))
        #expect(media.width == 4000)
        #expect(media.renditions.map(\.blobID) == [1, 2, 3, 4, 5].map(blobID))
        #expect(media.renditions.map(\.role) == [.thumbnail, .display, .thumbnail, .display, .thumbnail])
        #expect(media.renditions.first == MediaRendition(role: .thumbnail, blobID: blobID(1), width: 320, height: 160))
    }

    @Test("A derived rendition with no blob id is dropped")
    func mappingDropsMissingBlobID() throws {
        let media = try attachment(sized(.original, 4000, id: 6), .with { $0.role = .display; $0.blob.image.width = 800 })
        #expect(media.renditions.isEmpty)
    }

    @Test("A sealed photo has no derived renditions and always loads its ORIGINAL")
    func sealedLoadsOriginal() throws {
        let sealed = MediaAttachment(blobID: blobID(6), width: 4000, height: 3000, blurhash: nil, sealed: SealedBlob(senderID: UUID(), plaintextSize: 10))
        #expect(sealed.rendition(forPixelSize: 780)?.role == .original)
    }

    @Test("An attachment encoded before renditions decodes with none")
    func decodesWithoutRenditions() throws {
        let encoded = try JSONEncoder().encode(MediaAttachment(blobID: blobID(6), width: 10, height: 20, blurhash: nil))
        let decoded = try JSONDecoder().decode(MediaAttachment.self, from: encoded)
        #expect(decoded.renditions.isEmpty)
        // No renditions encodes no key, which is the shape an attachment written before them has.
        #expect(!String(decoding: encoded, as: UTF8.self).contains("derived"))
    }

    // MARK: Quote thumbnail (Android `QuoteThumbnailRenditionTest`)

    /// What the server returns for a plaintext photo: the original first, then what it derived.
    private func plaintext() throws -> MediaAttachment {
        try attachment(
            sized(.original, 4000, id: 1),
            sized(.thumbnail, 32, id: 2),
            sized(.thumbnail, 160, id: 3),
            sized(.thumbnail, 320, id: 4),
            sized(.display, 800, id: 5),
            sized(.display, 1600, id: 6)
        )
    }

    @Test("A plaintext photo quotes with the smallest thumbnail that covers the square")
    func quotePlaintext() throws {
        let media = try plaintext()
        #expect(media.quoteThumbnailBlobID == blobID(3))
        // Android's 40dp at 3x and 4x.
        for px in [120, 160] {
            #expect(media.rendition(forPixelSize: px)?.role == .thumbnail)
            #expect(media.rendition(forPixelSize: px)?.width == 160)
        }
    }

    @Test("A sealed photo quotes with its original")
    func quoteSealed() {
        let sealed = MediaAttachment(blobID: blobID(1), width: 4000, height: 3000, blurhash: nil, sealed: SealedBlob(senderID: UUID(), plaintextSize: 10))
        #expect(sealed.quoteThumbnailBlobID == blobID(1))
    }

    @Test("A photo the server derived nothing for quotes with its original")
    func quoteOriginalOnly() throws {
        #expect(try attachment(sized(.original, 4000, id: 1)).quoteThumbnailBlobID == blobID(1))
    }

    @Test("A photo whose blobs are not hydrated yet quotes with its original")
    func quoteUnhydrated() throws {
        let media = try attachment(unsized(.original, available: false, id: 1), unsized(.thumbnail, available: false, id: 2))
        #expect(media.quoteThumbnailBlobID == blobID(1))
    }

    @Test("An attachment with no blob yet has no thumbnail")
    func quoteNoBlob() {
        #expect(MediaAttachment(blobID: nil, width: 1, height: 1, blurhash: nil).quoteThumbnailBlobID == nil)
    }
}
