//
//  ChatPhotoStaging.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import UIKit
import FlipcashCore

private let logger = Logger(label: "flipcash.chat-photo-staging")

/// Turns photos picked from the library into composer chips.
enum ChatPhotoStaging {

    /// Loads `items` one at a time in pick order and stages each photo that loads, stopping at the
    /// first one the composer refuses for being full; returns the chips staged.
    @discardableResult
    static func stage<Item>(
        _ items: [Item],
        into composer: ComposerModel,
        uploader: ChatMediaUploader,
        load: (Item) async -> UIImage?
    ) async -> [ComposerChip] {
        var staged: [ComposerChip] = []
        for item in items {
            guard let image = await load(item) else { continue }
            guard let chip = composer.stageChip(image: image, uploader: uploader) else { break }
            staged.append(chip)
        }
        return staged
    }

    /// Stages photos added from the photo card in selection order: the leading run whose images
    /// `loaded` already holds at once, and the rest, from the first one still loading, through
    /// `load` without blocking the caller.
    ///
    /// Returns the first chip when it could be staged at once, for the card to shrink into, and the
    /// task staging the rest.
    static func stageAdded<Item>(
        _ items: [Item],
        into composer: ComposerModel,
        uploader: ChatMediaUploader,
        loaded: (Item) -> UIImage?,
        load: @escaping (Item) async -> UIImage?
    ) -> (handOff: ComposerChip.ID?, remainder: Task<[ComposerChip], Never>?) {
        var handOff: ComposerChip.ID?
        var index = items.startIndex
        while index < items.endIndex, let image = loaded(items[index]) {
            // The image is its own preview, so the chip has pixels on the hand-off's first frame.
            guard let chip = composer.stageChip(image: image, preview: image, uploader: uploader) else {
                return (handOff, nil)
            }
            if handOff == nil { handOff = chip.id }
            index += 1
        }
        let rest = Array(items[index...])
        guard !rest.isEmpty else { return (handOff, nil) }
        let remainder = Task {
            await stage(rest, into: composer, uploader: uploader, load: load)
        }
        return (handOff, remainder)
    }

    /// Returns the photo `item` holds, or `nil` when it cannot be loaded or decoded.
    static func loadImage(_ item: PhotosPickerItem) async -> UIImage? {
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else {
                logger.warning("Picked photo has no data")
                return nil
            }
            data = loaded
        } catch {
            // Usually an iCloud original that failed to download; nothing a developer can act on.
            logger.warning("Picked photo failed to load", metadata: ["error": "\(error)"])
            return nil
        }
        guard let image = await decode(data) else {
            logger.warning("Picked photo failed to decode", metadata: ["bytes": "\(data.count)"])
            return nil
        }
        return image
    }

    /// Returns the photo in `data` decoded at full size with its EXIF orientation drawn into the
    /// pixels, or `nil` when it cannot be decoded. Off the main actor, since a full-size photo takes
    /// a while to parse.
    ///
    /// Upright pixels, not an `imageOrientation`: `UIImageView` draws a turned image by rotating its
    /// layer's contents, and that rotation animates with the cell when a sent photo's bubble lands.
    @concurrent
    nonisolated static func decode(_ data: Data) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: upright)
    }
}
