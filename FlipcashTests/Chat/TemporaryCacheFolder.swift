//
//  TemporaryCacheFolder.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
@testable import FlipcashUI
import Kingfisher

/// A folder of its own in the test host's temporary directory for the caches one test writes,
/// removed with everything in it when this goes away. A cache made by name alone lands in the
/// app's Caches folder and stays there after the test.
final class TemporaryCacheFolder {

    let url: URL

    private var caches: [ImageCache] = []

    init() {
        url = FileManager.default.temporaryDirectory
            .appending(path: "chat-media-test-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    deinit {
        // Kingfisher writes to disk on each cache's own queue, and a write that lands after the
        // folder is removed makes the directory again. A cell or task can outlive the test and
        // finish a load later, so each cache stops storing first. A read queued behind writes
        // already under way finishes only once they have.
        for cache in caches {
            cache.diskStorage.config.expiration = .expired
            let drained = DispatchSemaphore(value: 0)
            cache.retrieveImageInDiskCache(forKey: "drain", callbackQueue: .untouch) { _ in drained.signal() }
            drained.wait()
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// An image cache stored inside this folder.
    func imageCache(named name: String) throws -> ImageCache {
        let cache = try ImageCache(name: name, cacheDirectoryURL: url)
        caches.append(cache)
        return cache
    }

    /// Chat photo caches stored inside this folder, standing in for ``ChatMediaCaches/shared``.
    func chatMediaCaches() throws -> ChatMediaCaches {
        try ChatMediaCaches(
            images: imageCache(named: "chat-media"),
            originals: imageCache(named: "chat-media-originals")
        )
    }

    /// An empty blob store inside this folder, standing in for the App Group's
    /// ``BlobCache/chatPhotos``.
    func pushedPhotos() -> BlobCache {
        BlobCache(directory: url.appending(path: "pushed-photos", directoryHint: .isDirectory), limitBytes: 32 * 1024 * 1024)
    }
}
