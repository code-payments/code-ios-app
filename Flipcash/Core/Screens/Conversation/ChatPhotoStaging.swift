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

    /// Decodes off the main actor, since a full-size photo takes a while to parse.
    @concurrent
    private nonisolated static func decode(_ data: Data) async -> UIImage? {
        UIImage(data: data)
    }
}
