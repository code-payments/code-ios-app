//
//  ChatMediaCachedDrawTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI
import Kingfisher

/// A photo already on the device draws from the cache without waiting on its signed URL.
@Suite("Chat photo drawn from the cache")
@MainActor
struct ChatMediaCachedDrawTests {

    private let folder: TemporaryCacheFolder
    private let caches: ChatMediaCaches
    private let pushed: BlobCache

    init() throws {
        let folder = TemporaryCacheFolder()
        self.folder = folder
        caches = try folder.chatMediaCaches()
        pushed = folder.pushedPhotos()
    }

    @MainActor
    private final class FetchSpy {
        var calls: [BlobID] = []
    }

    /// A small opaque image, unlike any BlurHash, so a test can tell the photo itself was drawn.
    private static let photo: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 7, height: 5), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 7, height: 5))
        }
    }()

    private func uniqueBlobID() -> BlobID {
        BlobID(data: Data(UUID().uuidString.utf8))
    }

    private func media(_ blobID: BlobID, isRedacted: Bool = false, sealed: SealedBlob? = nil) -> ChatMediaContent {
        ChatMediaContent(blobID: blobID, width: 1179, height: 2556, blurhash: nil, caption: nil, isRedacted: isRedacted, sealed: sealed)
    }

    /// Writes `photo` to disk under the key and processor the cell draws `media` with at
    /// `maxWidth`, then drops it from memory, as after a relaunch.
    private func cacheOnDiskOnly(_ media: ChatMediaContent, maxWidth: CGFloat) async throws -> (key: String, processor: ImageProcessor) {
        try await cacheOnDiskOnly(media, processor: ChatMediaCell.processor(for: media, maxWidth: maxWidth))
    }

    /// Writes `photo` to disk under the key `processor` draws `media` with, then drops it from
    /// memory, as after a relaunch.
    private func cacheOnDiskOnly(_ media: ChatMediaContent, processor: ImageProcessor) async throws -> (key: String, processor: ImageProcessor) {
        let blobID = try #require(media.blobID)
        let key = ChatMediaImageSource.cacheKey(for: blobID)
        await withCheckedContinuation { continuation in
            ChatMediaImageSource.persist(Self.photo, cacheType: .none, forKey: key, processor: processor, in: caches) {
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            caches.images.removeImage(
                forKey: key,
                processorIdentifier: processor.identifier,
                fromMemory: true,
                fromDisk: false
            ) { continuation.resume() }
        }
        #expect(caches.images.imageCachedType(forKey: key, processorIdentifier: processor.identifier) == .disk)
        return (key, processor)
    }

    /// Waits up to two seconds for `view` to draw an image.
    private func drawnImage(_ view: () -> UIImageView?) async -> UIImage? {
        for _ in 0..<200 where view()?.image == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return view()?.image
    }

    // MARK: - Cell -

    @Test("A photo cached on disk draws with no URL")
    func diskCachedPhotoDrawsWithoutURL() async throws {
        let media = media(uniqueBlobID())
        _ = try await cacheOnDiskOnly(media, maxWidth: 240)

        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true), maxWidth: 240, localImage: nil, remote: .cached(sealed: false, in: caches))

        let drawn = await drawnImage { cell.imageView }
        #expect(drawn?.cgImage?.width == 7)
    }

    @Test("A row drawing a cached copy that has gone asks to be configured again, once")
    func goneCachedCopyReloads() async throws {
        let media = media(uniqueBlobID())
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        var reloads = 0
        cell.onReload = { reloads += 1 }
        cell.configure(with: ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true), maxWidth: 240, localImage: nil, remote: .cached(sealed: false, in: caches))

        for _ in 0..<200 where reloads == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(reloads == 1)
    }

    // MARK: - Resolver -

    @Test("A photo cached as its row draws it resolves to the cache without minting")
    func resolverPrefersTheCache() async throws {
        let spy = FetchSpy()
        let resolver = ChatMediaURLResolver(fetch: { blobID in
            spy.calls.append(blobID)
            return BlobDownloadLink(url: URL(string: "https://example.invalid/photo")!)
        }, caches: caches, pushedPhotos: pushed)
        let media = media(uniqueBlobID())
        let processor = ChatMediaCell.processor(for: media, maxWidth: 240)
        _ = try await cacheOnDiskOnly(media, processor: processor)

        let location = resolver.location(for: media, canReact: true, drawing: ChatMediaBubbleLoad(media: media, maxWidth: 240, scale: 3)) { _ in }
        #expect(location != nil)
        #expect(location?.url == nil)
        await Task.yield()
        #expect(spy.calls.isEmpty)
    }

    @Test("A full-size copy left by the viewer also counts as cached")
    func resolverTakesTheFullSizeCopy() async throws {
        let resolver = ChatMediaURLResolver(fetch: { _ in nil }, caches: caches, pushedPhotos: pushed)
        let media = media(uniqueBlobID())
        _ = try await cacheOnDiskOnly(media, processor: DefaultImageProcessor.default)

        let location = resolver.location(for: media, canReact: true, drawing: ChatMediaBubbleLoad(media: media, maxWidth: 240, scale: 3)) { _ in }
        #expect(location != nil)
        #expect(location?.url == nil)
    }

    @Test("A sealed photo drawn from the cache still logs as sealed")
    func cachedSealedPhotoLogsAsSealed() async throws {
        let resolver = ChatMediaURLResolver(fetch: { _ in nil }, caches: caches, pushedPhotos: pushed)
        let media = media(uniqueBlobID(), sealed: SealedBlob(senderID: UUID(), plaintextSize: 10))
        let processor = ChatMediaCell.processor(for: media, maxWidth: 240)
        _ = try await cacheOnDiskOnly(media, processor: processor)

        let location = try #require(resolver.location(for: media, canReact: true, drawing: ChatMediaBubbleLoad(media: media, maxWidth: 240, scale: 3)) { _ in })
        let result = await ChatMediaImageSource.retrieve(
            ChatMediaImageSource.source(blobID: media.blobID, location: location),
            options: ChatMediaImageSource.options(processor: processor, in: caches)
        )
        let report = ChatMediaLoadReport(result, blobID: media.blobID, surface: .bubble)

        #expect(report.cache == .disk)
        #expect(report.metadata["sealed"] == "true")
    }

    @Test("A photo not cached mints its URL")
    func resolverMintsOnACacheMiss() async throws {
        let spy = FetchSpy()
        let resolver = ChatMediaURLResolver(fetch: { blobID in
            spy.calls.append(blobID)
            return nil
        }, caches: caches, pushedPhotos: pushed)
        let media = media(uniqueBlobID())

        #expect(resolver.location(for: media, canReact: true, drawing: ChatMediaBubbleLoad(media: media, maxWidth: 240, scale: 3)) { _ in } == nil)
        for _ in 0..<100 where spy.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(spy.calls.count == 1)
    }

    @Test("A redacted photo never resolves to the cache")
    func resolverKeepsRedactedOffTheCache() async throws {
        let resolver = ChatMediaURLResolver(fetch: { _ in nil }, caches: caches, pushedPhotos: pushed)
        let blobID = uniqueBlobID()
        let processor = ChatMediaCell.processor(for: media(blobID), maxWidth: 240)
        _ = try await cacheOnDiskOnly(media(blobID), processor: processor)

        #expect(resolver.location(for: media(blobID, isRedacted: true), canReact: true, drawing: ChatMediaBubbleLoad(media: media(blobID), maxWidth: 240, scale: 3)) { _ in } == nil)
    }

    @Test("A redacted photo stays on its BlurHash even when its bytes are cached")
    func redactedPhotoIgnoresTheCache() async throws {
        let blobID = uniqueBlobID()
        _ = try await cacheOnDiskOnly(media(blobID), maxWidth: 240)

        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media(blobID, isRedacted: true)), sender: .other, canReact: true),
            maxWidth: 240,
            localImage: nil,
            remote: nil
        )

        try? await Task.sleep(for: .milliseconds(200))
        #expect(cell.imageView.image == nil)
    }

    // MARK: - Transcript -

    private func photoView(in controller: ChatViewController) -> UIImageView? {
        controller.collectionView.visibleCells.lazy.compactMap { ($0 as? ChatMediaCell)?.imageView }.first
    }

    private func show(_ controller: ChatViewController, _ message: ChatMessage) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: [.message(message)])
        window.layoutIfNeeded()
        return window
    }

    @Test("Re-opening a chat draws a photo it already loaded without minting its URL again")
    func reopenedChatDrawsWithoutMinting() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-media-\(UUID().uuidString)")
        let bytes = try #require(Self.photo.pngData())
        try bytes.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let media = media(uniqueBlobID(), sealed: SealedBlob(senderID: UUID(), plaintextSize: bytes.count))
        let message = ChatMessage(id: "photo", content: .media(media), sender: .other, canReact: true)

        // The first open mints the URL and downloads the photo.
        let firstOpen = FetchSpy()
        let opened = ChatViewController()
        opened.mediaURLResolver = ChatMediaURLResolver(
            fetch: { blobID in
                firstOpen.calls.append(blobID)
                return BlobDownloadLink(url: file)
            },
            decrypt: { { blob, _, _ in blob } },
            caches: caches,
            pushedPhotos: pushed
        )
        let firstWindow = show(opened, message)
        #expect(await drawnImage { photoView(in: opened) }?.cgImage?.width == 7)
        #expect(firstOpen.calls.count == 1)
        firstWindow.isHidden = true

        // A new screen starts with an empty URL cache, as every re-open does.
        let reopen = FetchSpy()
        let reopened = ChatViewController()
        reopened.mediaURLResolver = ChatMediaURLResolver(fetch: { blobID in
            reopen.calls.append(blobID)
            return nil
        }, caches: caches, pushedPhotos: pushed)
        let window = show(reopened, message)
        defer { window.isHidden = true }

        let drawn = await drawnImage { photoView(in: reopened) }
        #expect(drawn?.cgImage?.width == 7, "drew \(String(describing: drawn)) from \(reopen.calls.count) mints")
        await Task.yield()
        #expect(reopen.calls.isEmpty)
    }
}
