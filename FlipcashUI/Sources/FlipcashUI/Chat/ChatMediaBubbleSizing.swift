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
    /// The tallest a photo may draw: 2:1, height over width.
    static let maxAspect: Double = 2.0

    /// A bubble's footprint, and whether the photo is centre-cropped to fit it.
    struct Size: Equatable {
        let width: Double
        let height: Double
        let cropped: Bool
    }

    /// The bubble for a `imageWidth` × `imageHeight` photo: always `maxWidth` wide, its height following
    /// the photo's aspect clamped to 1:2…2:1. A photo missing either dimension draws square.
    static func size(imageWidth: Double, imageHeight: Double, maxWidth: Double) -> Size {
        guard imageWidth > 0, imageHeight > 0 else {
            return Size(width: maxWidth, height: maxWidth, cropped: false)
        }
        let aspect = imageHeight / imageWidth
        let clamped = min(max(aspect, minAspect), maxAspect)
        return Size(width: maxWidth, height: maxWidth * clamped, cropped: clamped != aspect)
    }
}
