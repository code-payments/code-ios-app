//
//  MediaRendition.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One copy of a photo the server stores under its own blob: the ORIGINAL the sender uploaded, or a
/// smaller DISPLAY or THUMBNAIL size it derived from it.
public struct MediaRendition: Hashable, Sendable, Codable {

    public enum Role: String, Hashable, Sendable, Codable {
        case original
        case display
        case thumbnail
        /// A role this build does not know, kept so selection treats it as Android does.
        case unknown
    }

    public let role: Role
    public let blobID: BlobID
    /// Pixel width, or nil when the server described no image dimensions for this copy.
    public let width: Int?
    /// Pixel height, or nil when the server described no image dimensions for this copy.
    public let height: Int?

    public init(role: Role, blobID: BlobID, width: Int?, height: Int?) {
        self.role = role
        self.blobID = blobID
        self.width = width
        self.height = height
    }

    /// The longer of the two sides, or nil without dimensions.
    var longestSide: Int? {
        guard let width, let height else { return nil }
        return max(width, height)
    }
}

// MARK: - Selection -

extension MediaRendition {

    /// The rendition a photo drawn `targetPixels` on its longest side loads: the smallest derived
    /// copy that covers it, else the largest derived copy, else `original`.
    ///
    /// A port of Android's `photoRendition` (`MediaItem.renditionForSize` falling back to the
    /// ORIGINAL), so both apps download the same copy for the same bubble.
    public static func forPixelSize(_ targetPixels: Int, derived: [MediaRendition], original: MediaRendition?) -> MediaRendition? {
        self.derived(forPixelSize: targetPixels, in: derived) ?? original
    }

    /// Android's `MediaItem.renditionForSize`: among the derived copies that carry dimensions, the
    /// smallest whose longest side reaches `targetPixels`, or the largest when none does. With no
    /// sized derived copy, the role ladder from DISPLAY down: the first DISPLAY, else the first
    /// THUMBNAIL. Nil when there is no derived copy to use.
    ///
    /// Every entry in `renditions` is one the server has a blob for; mapping drops the rest.
    static func derived(forPixelSize targetPixels: Int, in renditions: [MediaRendition]) -> MediaRendition? {
        let sized = renditions.enumerated().compactMap { index, rendition in
            rendition.role == .original ? nil : rendition.longestSide.map { (rendition: rendition, side: $0, index: index) }
        }
        guard !sized.isEmpty else { return firstOnLadder(from: .display, in: renditions) }
        // Ties keep list order, as Kotlin's stable `sortedBy` does: the first of equal covering
        // sizes wins, and `last` takes the last of equal largest ones.
        let ranked = sized.sorted { ($0.side, $0.index) < ($1.side, $1.index) }
        return (ranked.first { $0.side >= targetPixels } ?? ranked[ranked.count - 1]).rendition
    }

    /// Android's `MediaItem.rendition(preferred:)`: the first rendition of `preferred`'s role, else
    /// of each lower-quality role in turn. It never climbs above `preferred`.
    private static func firstOnLadder(from preferred: Role, in renditions: [MediaRendition]) -> MediaRendition? {
        let ladder: [Role] = [.original, .display, .thumbnail]
        guard let start = ladder.firstIndex(of: preferred) else { return nil }
        for role in ladder[start...] {
            if let rendition = renditions.first(where: { $0.role == role }) { return rendition }
        }
        return nil
    }
}

// MARK: - Proto -

extension MediaRendition {

    /// The derived copy `proto` describes, or nil for the ORIGINAL (carried by ``MediaAttachment``'s
    /// own fields), an entry with no blob id, or one whose blob the server has not produced yet.
    init?(derived proto: Flipcash_Blob_V1_Rendition) {
        let role: Role
        switch proto.role {
        case .original:                return nil
        case .display:                 role = .display
        case .thumbnail:               role = .thumbnail
        case .unknown, .UNRECOGNIZED:  role = .unknown
        }
        guard proto.hasBlobID, proto.hasBlob else { return nil }
        let image: Flipcash_Blob_V1_ImageMetadata?
        if case .image(let metadata)? = proto.blob.kind { image = metadata } else { image = nil }
        self.init(
            role: role,
            blobID: BlobID(data: proto.blobID.value),
            width: image.map { Int($0.width) },
            height: image.map { Int($0.height) }
        )
    }
}
