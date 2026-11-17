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

        let downloader = ImageDownloader(name: "chat-media-retrieve-test")
        let cache = ImageCache(name: "chat-media-retrieve-test-\(UUID().uuidString)")
        let manager = KingfisherManager(downloader: downloader, cache: cache)
        let url = URL(string: "http://127.0.0.1:\(port)/photo-\(UUID().uuidString).png")!

        let result = await ChatMediaImageSource.retrieve(.network(url), options: [.targetCache(cache)], manager: manager)

        let value = try result.get()
        #expect(value.cacheType == .none)
        #expect(value.metrics != nil)
    }
}
