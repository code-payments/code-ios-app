//
//  ChatPhotoDecoder.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import CoreGraphics
import Foundation
import ImageIO

/// Decodes photo bytes into upright pixels through ImageIO.
public enum ChatPhotoDecoder {

    /// Returns the photo in `data` with its EXIF orientation drawn into the pixels, or `nil` when it
    /// cannot be decoded. Full size unless `maxPixelSize` caps the longer edge. Off the caller's
    /// actor, since a full-size photo takes a while to parse.
    @concurrent
    public static func decode(_ data: Data, maxPixelSize: Int? = nil) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return upright(source, maxPixelSize: maxPixelSize)
    }

    /// Returns the photo at `url` as ``decode(_:maxPixelSize:)`` does, reading the file through
    /// ImageIO rather than into memory first.
    @concurrent
    public static func decode(contentsOf url: URL, maxPixelSize: Int? = nil) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return upright(source, maxPixelSize: maxPixelSize)
    }

    private static func upright(_ source: CGImageSource, maxPixelSize: Int?) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        let longestEdge = max(width, height)
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize.map { min($0, longestEdge) } ?? longestEdge,
        ] as CFDictionary)
    }
}
