//
//  ChatMediaBubbleSizing.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The size a photo bubble draws at, known from the photo's dimensions before any bytes arrive.
nonisolated enum ChatMediaBubbleSizing {

    /// The widest a photo may draw: 1:2, height over width.
    static let minAspect: Double = 0.5
    /// The tallest a photo may draw: 5:4, height over width. A 3:4 portrait camera photo crops a little.
    static let maxAspect: Double = 1.25

    /// A bubble's footprint, and whether the photo is centre-cropped to fit it.
    struct Size: Equatable {
        let width: Double
        let height: Double
        let cropped: Bool
    }

    /// The bubble for a stack of photos: a `maxWidth` square, whatever the photos' shape.
    static func stackSize(maxWidth: Double) -> Size {
        Size(width: maxWidth, height: maxWidth, cropped: true)
    }

    /// The bubble for a `imageWidth` × `imageHeight` photo: always `maxWidth` wide, its height following
    /// the photo's aspect clamped to 1:2…5:4. A photo missing either dimension draws square.
    static func size(imageWidth: Double, imageHeight: Double, maxWidth: Double) -> Size {
        guard imageWidth > 0, imageHeight > 0 else {
            return Size(width: maxWidth, height: maxWidth, cropped: false)
        }
        let aspect = imageHeight / imageWidth
        let clamped = min(max(aspect, minAspect), maxAspect)
        return Size(width: maxWidth, height: maxWidth * clamped, cropped: clamped != aspect)
    }
}
