//
//  ChatMediaCaches.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Kingfisher

/// The disk caches chat photos read and write. Every load, probe and store names the caches it
/// uses, so a test can pass caches in a temporary folder instead of the app's.
nonisolated public final class ChatMediaCaches: Sendable {

    /// The copies each bubble, quote and viewer draws, keyed by blob. A blob's bytes never change,
    /// so unlike the app's other remote images they persist to disk and never expire from memory.
    public let images: ImageCache

    /// The decrypted bytes of each downloaded photo exactly as sent. `images` holds only a decoded
    /// copy re-serialized as JPEG, which would turn a PNG or HEIC into a lossy JPEG on save.
    let originals: ImageCache

    init(images: ImageCache, originals: ImageCache) {
        images.memoryStorage.config.expiration = .never
        images.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        images.diskStorage.config.expiration = .days(30)
        originals.diskStorage.config.sizeLimit = 500 * 1024 * 1024
        originals.diskStorage.config.expiration = .days(30)
        self.images = images
        self.originals = originals
    }

    /// The app's chat photo caches.
    public static let shared = ChatMediaCaches(
        images: ImageCache(name: "chat-media"),
        originals: ImageCache(name: "chat-media-originals")
    )
}
