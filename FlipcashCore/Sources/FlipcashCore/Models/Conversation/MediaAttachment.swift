//
//  MediaAttachment.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One photo attached to a chat message: the ORIGINAL rendition's blob and the intrinsic metadata
/// needed to lay it out before its bytes arrive.
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

    public init(blobID: BlobID?, width: Int, height: Int, blurhash: String?) {
        self.blobID   = blobID
        self.width    = width
        self.height   = height
        self.blurhash = blurhash
    }
}

// MARK: - Proto -

extension MediaAttachment {

    /// Returns the attachment described by `proto`'s ORIGINAL rendition, or `nil` when it carries none.
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
            blurhash: image.blurhash.isEmpty ? nil : image.blurhash
        )
    }

    /// The single-ORIGINAL `Media` a client attaches on send; `nil` when there is no blob to attach.
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
