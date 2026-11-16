//
//  MediaAttachment.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One photo attached to a chat message: the ORIGINAL rendition's blob, the intrinsic metadata
/// needed to lay it out before its bytes arrive, and the smaller copies the server derived from it.
public struct MediaAttachment: Hashable, Sendable, Codable {

    /// The ORIGINAL rendition's blob; `nil` only for an optimistic row whose upload has not
    /// produced one yet.
    public let blobID: BlobID?

    /// Pixel width of the ORIGINAL.
    public let width: Int

    /// Pixel height of the ORIGINAL.
    public let height: Int

    /// The ORIGINAL's BlurHash preview, or `nil` when the server carried none.
    public let blurhash: String?

    /// How the blob decrypts when it is end-to-end encrypted for the chat; nil for a plaintext blob.
    public let sealed: SealedBlob?

    /// Optional so an attachment encoded before renditions still decodes.
    private let derived: [MediaRendition]?

    /// The DISPLAY and THUMBNAIL copies the server derived and holds a blob for, in its order. Empty
    /// for a sealed photo, which the server can't read, and for one it is still processing.
    public var renditions: [MediaRendition] { derived ?? [] }

    public init(blobID: BlobID?, width: Int, height: Int, blurhash: String?, sealed: SealedBlob? = nil, renditions: [MediaRendition] = []) {
        self.blobID   = blobID
        self.width    = width
        self.height   = height
        self.blurhash = blurhash
        self.sealed   = sealed
        self.derived  = renditions.isEmpty ? nil : renditions
    }

    /// The ORIGINAL as a rendition, or nil before its upload produced a blob.
    public var original: MediaRendition? {
        blobID.map { MediaRendition(role: .original, blobID: $0, width: width, height: height) }
    }

    /// The copy a view drawing this photo `targetPixels` on its longest side loads. See
    /// ``MediaRendition/forPixelSize(_:derived:original:)``.
    public func rendition(forPixelSize targetPixels: Int) -> MediaRendition? {
        MediaRendition.forPixelSize(targetPixels, derived: renditions, original: original)
    }

    /// The longest side, in pixels, of a quoted photo's thumbnail: 38 pt at 3x, the reply strip's
    /// square and the larger of the two places a quote draws one.
    public static let quoteThumbnailPixelSize = 114

    /// The blob a quote of this photo draws its thumbnail from, picked as a bubble picks its copy.
    public var quoteThumbnailBlobID: BlobID? {
        rendition(forPixelSize: Self.quoteThumbnailPixelSize)?.blobID
    }
}

/// What an end-to-end encrypted photo's blob needs, besides the chat key, to be decrypted and
/// checked: who uploaded it, which orders the public keys in its aad, and the plaintext length the
/// decrypted bytes must match.
public struct SealedBlob: Hashable, Sendable, Codable {
    /// The member who uploaded the blob, always the sender of the message that references it.
    public let senderID: UserID
    /// The plaintext image's length in bytes, from the sender's sealed metadata.
    public let plaintextSize: Int

    public init(senderID: UserID, plaintextSize: Int) {
        self.senderID = senderID
        self.plaintextSize = plaintextSize
    }
}

// MARK: - Proto -

extension MediaAttachment {

    /// Returns the attachment described by `proto`'s ORIGINAL rendition and the derived copies beside
    /// it, or `nil` when it carries no ORIGINAL.
    ///
    /// A redacted copy still maps: the server keeps its dimensions and blurhash and drops only the
    /// download URL, which this type never carries.
    init?(_ proto: Flipcash_Blob_V1_Media) {
        guard let original = proto.renditions.first(where: { $0.role == .original }) else {
            return nil
        }
        let image = original.blob.image
        self.init(
            blobID: original.hasBlobID ? BlobID(data: original.blobID.value) : nil,
            width: Int(image.width),
            height: Int(image.height),
            blurhash: image.blurhash.isEmpty ? nil : image.blurhash,
            renditions: proto.renditions.compactMap(MediaRendition.init(derived:))
        )
    }

    /// The single-ORIGINAL `Media` a client attaches on send; `nil` when there is no blob to attach.
    /// The server derives the other renditions itself.
    var proto: Flipcash_Blob_V1_Media? {
        guard let blobID else { return nil }
        return .with {
            $0.renditions = [.with {
                $0.role = .original
                $0.blobID = .with { $0.value = blobID.data }
            }]
        }
    }
}
