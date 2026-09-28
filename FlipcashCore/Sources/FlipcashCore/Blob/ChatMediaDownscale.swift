//
//  ChatMediaDownscale.swift
//  FlipcashCore
//

import Foundation

/// The single scale factor a chat photo is downscaled by before upload — pure math, no image
/// codec, so it can be pinned by `chat_media.json`'s `downscale` section without a UIKit
/// dependency. `ChatMediaEncoder` is what actually re-encodes at this target.
public enum ChatMediaDownscale {

    public struct Target: Equatable, Sendable {
        public let width: Int
        public let height: Int
    }

    /// `maxWidth`/`maxHeight`/`maxPixels` of `0` mean unbounded on that axis. Never upscales —
    /// the resulting edges are always `<= source`.
    public static func target(sourceWidth w: Int, sourceHeight h: Int, maxWidth: Int, maxHeight: Int, maxPixels: Int) -> Target {
        guard w > 0, h > 0 else { return Target(width: max(w, 1), height: max(h, 1)) }

        var scale = 1.0
        if maxWidth > 0 { scale = min(scale, Double(maxWidth) / Double(w)) }
        if maxHeight > 0 { scale = min(scale, Double(maxHeight) / Double(h)) }
        if maxPixels > 0 {
            let pixelScale = (Double(maxPixels) / (Double(w) * Double(h))).squareRoot()
            scale = min(scale, pixelScale)
        }

        var targetWidth = max(Int(Double(w) * scale), 1)
        var targetHeight = max(Int(Double(h) * scale), 1)

        // Flooring both edges independently can still leave the product over maxPixels by a
        // pixel or two; shave the longer edge until it fits rather than re-deriving scale.
        if maxPixels > 0 {
            while targetWidth * targetHeight > maxPixels, targetWidth > 1 || targetHeight > 1 {
                if targetWidth >= targetHeight {
                    targetWidth -= 1
                } else {
                    targetHeight -= 1
                }
            }
        }

        return Target(width: targetWidth, height: targetHeight)
    }
}
