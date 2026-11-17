//
//  ChatMediaBubbleLoad.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import FlipcashCore
import Kingfisher

/// What a photo bubble loads: which copy of the photo it downloads, and the processor that
/// downsamples it and keys its cached copy.
///
/// The transcript asks its resolver for this copy and the bubble draws it, so the cache probe,
/// the URL mint and the key the bubble draws under all come from one place.
public struct ChatMediaBubbleLoad {

    /// The copy the bubble downloads: the smallest derived copy that covers the bubble's width in
    /// pixels, else the ORIGINAL. See ``MediaRendition/forPixelSize(_:derived:original:)``.
    public let rendition: MediaRendition

    /// How the downloaded copy is downsampled, which keys its cached copy.
    public let processor: ImageProcessor

    /// The load for `media` drawn in a transcript whose widest bubble is `maxWidth` points, on a
    /// screen of `scale` pixels per point. Nil for a pending photo whose upload has no blob yet.
    public init?(media: ChatMediaContent, maxWidth: CGFloat, scale: CGFloat) {
        guard let rendition = media.rendition(forPixelSize: Self.targetPixels(maxWidth: maxWidth, scale: scale)) else {
            return nil
        }
        self.rendition = rendition
        self.processor = ChatMediaCell.processor(for: media, maxWidth: maxWidth)
    }

    /// The pixel size a bubble's copy must reach: the bubble's width, which a photo always spans,
    /// as Android's bubble asks for `maxWidth.roundToPx()`. A view not yet on a screen reports a
    /// scale of 0; that is taken as 3, so its copy never draws soft once it is.
    static func targetPixels(maxWidth: CGFloat, scale: CGFloat) -> Int {
        Int((maxWidth * (scale > 0 ? scale : 3)).rounded())
    }
}
