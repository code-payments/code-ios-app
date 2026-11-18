//
//  ChatMediaRetrieveTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
@testable import FlipcashUI
import Kingfisher

@Suite("Chat photo retrieve")
@MainActor
struct ChatMediaRetrieveTests {

    /// Link cards and the viewer load through `retrieve`, not an image view. Kingfisher reads a
    /// download's timings after decoding it, through a weak reference that only the returned task
    /// keeps alive, so a load that drops the task logs no timings.
    @Test("A network load outside an image view reports its timings")
    func networkLoadKeepsMetrics() async throws {
        let server = try LoopbackPhotoServer()
        let port = try await server.start()
        defer { server.stop() }
        let folder = TemporaryCacheFolder()

        let downloader = ImageDownloader(name: "chat-media-retrieve-test")
        let cache = try folder.imageCache(named: "chat-media-retrieve-test")
        let manager = KingfisherManager(downloader: downloader, cache: cache)
        let url = URL(string: "http://127.0.0.1:\(port)/photo-\(UUID().uuidString).png")!

        let result = await ChatMediaImageSource.retrieve(.network(url), options: [.targetCache(cache)], manager: manager)

        let value = try result.get()
        #expect(value.cacheType == .none)
        #expect(value.metrics != nil)
    }

    @Test("A test's cache lives outside the app's Caches folder and is removed when the test ends")
    func testCacheIsRemoved() throws {
        var folder: TemporaryCacheFolder? = TemporaryCacheFolder()
        let cache = try #require(folder).imageCache(named: "chat-media-retrieve-test")
        try cache.diskStorage.store(value: Data("photo".utf8), forKey: "photo")
        let directory = cache.diskStorage.directoryURL.standardizedFileURL
        let appCaches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first).standardizedFileURL
        #expect(!directory.path.hasPrefix(appCaches.path))
        #expect(FileManager.default.fileExists(atPath: directory.path))

        folder = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Kingfisher writes to disk on its own queue after a load returns, and a write that lands
    /// after the folder is gone makes the directory again.
    @Test("A disk write still queued when the test ends does not bring the folder back")
    func queuedWriteIsDrained() async throws {
        var folder: TemporaryCacheFolder? = TemporaryCacheFolder()
        let cache = try #require(folder).imageCache(named: "chat-media-retrieve-test")
        let directory = cache.diskStorage.directoryURL
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        cache.store(image, forKey: "photo", completionHandler: nil)

        folder = nil
        _ = try await cache.retrieveImageInDiskCache(forKey: "photo")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
