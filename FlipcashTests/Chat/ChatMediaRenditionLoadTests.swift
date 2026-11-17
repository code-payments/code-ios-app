//
//  ChatMediaRenditionLoadTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI
@testable import Flipcash
import Kingfisher

/// A photo bubble loads the smallest copy the server derived that covers it, and still draws a
/// photo cached under its ORIGINAL before renditions were loaded.
@Suite("Chat photo bubble renditions")
@MainActor
struct ChatMediaRenditionLoadTests {

    private let folder: TemporaryCacheFolder
    private let caches: ChatMediaCaches

    init() throws {
        let folder = TemporaryCacheFolder()
        self.folder = folder
        caches = try folder.chatMediaCaches()
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

    /// A blob no other test touches, since the cache is shared and on disk.
    private func uniqueBlobID() -> BlobID {
        BlobID(data: Data(UUID().uuidString.utf8))
    }

    private struct Blobs {
        let original: BlobID
        let display: BlobID
        let thumbnail: BlobID
    }

    private func blobs() -> Blobs {
        Blobs(original: uniqueBlobID(), display: uniqueBlobID(), thumbnail: uniqueBlobID())
    }

    private func display(_ blobs: Blobs) -> MediaRendition {
        MediaRendition(role: .display, blobID: blobs.display, width: 1080, height: 1440)
    }

    private func thumbnail(_ blobs: Blobs) -> MediaRendition {
        MediaRendition(role: .thumbnail, blobID: blobs.thumbnail, width: 120, height: 160)
    }

    /// A 3024 × 4032 photo with the DISPLAY and THUMBNAIL copies the server derives for it.
    private func media(_ blobs: Blobs, derived: Bool = true, sealed: SealedBlob? = nil) -> ChatMediaContent {
        ChatMediaContent(
            blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, caption: nil,
            isRedacted: false, sealed: sealed,
            renditions: derived ? [display(blobs), thumbnail(blobs)] : []
        )
    }

    private func load(_ media: ChatMediaContent, maxWidth: CGFloat = 240, scale: CGFloat = 3) throws -> ChatMediaBubbleLoad {
        try #require(ChatMediaBubbleLoad(media: media, maxWidth: maxWidth, scale: scale))
    }

    /// Writes `photo` to disk under `blobID`'s key as `processor` draws it, then drops it from
    /// memory, as after a relaunch.
    private func cacheOnDiskOnly(_ blobID: BlobID, processor: ImageProcessor) async -> (key: String, processor: ImageProcessor) {
        let key = ChatMediaImageSource.cacheKey(for: blobID)
        await withCheckedContinuation { continuation in
            ChatMediaImageSource.persist(Self.photo, cacheType: .none, forKey: key, processor: processor, in: caches) {
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            caches.images.removeImage(forKey: key, processorIdentifier: processor.identifier, fromMemory: true, fromDisk: false) {
                continuation.resume()
            }
        }
        #expect(caches.images.imageCachedType(forKey: key, processorIdentifier: processor.identifier) == .disk)
        return (key, processor)
    }

    private func resolver(_ spy: FetchSpy) -> ChatMediaURLResolver {
        ChatMediaURLResolver(fetch: { blobID in
            spy.calls.append(blobID)
            return nil
        }, caches: caches)
    }

    /// Waits up to two seconds for `view` to draw an image.
    private func drawnImage(_ view: () -> UIImageView?) async -> UIImage? {
        for _ in 0..<200 where view()?.image == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return view()?.image
    }

    // MARK: - Selection -

    @Test("A plaintext bubble loads the smallest derived copy that covers its width in pixels")
    func bubbleLoadsDisplay() throws {
        let blobs = blobs()
        // 240 pt at 3x is 720 px: the 160 px THUMBNAIL is too small, the 1440 px DISPLAY covers it.
        #expect(try load(media(blobs)).rendition == display(blobs))
    }

    @Test("The target is the bubble's width times the screen scale")
    func targetIsWidthTimesScale() throws {
        let blobs = blobs()
        #expect(try load(media(blobs), maxWidth: 50, scale: 3).rendition == thumbnail(blobs))
        #expect(try load(media(blobs), maxWidth: 60, scale: 3).rendition == display(blobs))
        #expect(try load(media(blobs), maxWidth: 60, scale: 2).rendition == thumbnail(blobs))
    }

    @Test("A photo the server has derived nothing for yet loads its ORIGINAL")
    func noDerivedLoadsOriginal() throws {
        let blobs = blobs()
        let rendition = try load(media(blobs, derived: false)).rendition
        #expect(rendition.role == .original)
        #expect(rendition.blobID == blobs.original)
    }

    @Test("A sealed photo loads its ORIGINAL even with derived copies listed")
    func sealedLoadsOriginal() throws {
        let blobs = blobs()
        let rendition = try load(media(blobs, sealed: SealedBlob(senderID: UUID(), plaintextSize: 10))).rendition
        #expect(rendition.role == .original)
        #expect(rendition.blobID == blobs.original)
    }

    @Test("A pending photo with no blob has nothing to load")
    func pendingHasNoLoad() {
        let media = ChatMediaContent(blobID: nil, width: 10, height: 10, blurhash: nil, caption: nil, isRedacted: false)
        #expect(ChatMediaBubbleLoad(media: media, maxWidth: 240, scale: 3) == nil)
    }

    @Test("The load downsamples with the processor the cell lays the photo out with")
    func processorMatchesTheCell() throws {
        let media = media(blobs())
        #expect(try load(media).processor.identifier == ChatMediaCell.processor(for: media, maxWidth: 240).identifier)
    }

    // MARK: - Resolver -

    @Test("A photo not cached mints its derived copy's URL, not the ORIGINAL's")
    func missMintsTheRendition() async throws {
        let spy = FetchSpy()
        let resolver = resolver(spy)
        let blobs = blobs()

        #expect(resolver.location(for: media(blobs), canReact: true, drawing: try load(media(blobs))) { _ in } == nil)
        for _ in 0..<100 where spy.calls.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(spy.calls == [blobs.display])
    }

    @Test("A minted location says which copy it draws")
    func mintedLocationCarriesItsRendition() async throws {
        let blobs = blobs()
        let resolver = ChatMediaURLResolver(fetch: { _ in BlobDownloadLink(url: URL(string: "https://example.invalid/display")!) }, caches: caches)
        let load = try load(media(blobs))

        let location = await withCheckedContinuation { continuation in
            let immediate = resolver.location(for: media(blobs), canReact: true, drawing: load) { continuation.resume(returning: $0) }
            if let immediate { continuation.resume(returning: immediate) }
        }
        #expect(location.rendition == display(blobs))
        #expect(location.url != nil)
    }

    @Test("A photo cached under its ORIGINAL before renditions loaded draws from that copy without minting")
    func originalKeyFallback() async throws {
        let spy = FetchSpy()
        let resolver = resolver(spy)
        let blobs = blobs()
        let media = media(blobs)
        let load = try load(media)
        let cached = await cacheOnDiskOnly(blobs.original, processor: load.processor)

        let location = try #require(resolver.location(for: media, canReact: true, drawing: load) { _ in })
        #expect(location.url == nil)
        #expect(location.rendition?.role == .original)
        #expect(ChatMediaImageSource.source(blobID: location.rendition?.blobID, location: location).cacheKey == cached.key)
        await Task.yield()
        #expect(spy.calls.isEmpty)
    }

    @Test("A full-size ORIGINAL the viewer left behind also counts as cached")
    func originalFullSizeFallback() async throws {
        let spy = FetchSpy()
        let blobs = blobs()
        _ = await cacheOnDiskOnly(blobs.original, processor: DefaultImageProcessor.default)

        let location = resolver(spy).location(for: media(blobs), canReact: true, drawing: try load(media(blobs))) { _ in }
        #expect(location?.url == nil)
        #expect(location?.rendition?.role == .original)
        await Task.yield()
        #expect(spy.calls.isEmpty)
    }

    @Test("With both copies cached, the derived one draws")
    func renditionKeyWins() async throws {
        let blobs = blobs()
        let load = try load(media(blobs))
        _ = await cacheOnDiskOnly(blobs.original, processor: load.processor)
        _ = await cacheOnDiskOnly(blobs.display, processor: load.processor)

        let location = resolver(FetchSpy()).location(for: media(blobs), canReact: true, drawing: load) { _ in }
        #expect(location?.url == nil)
        #expect(location?.rendition == display(blobs))
    }

    @Test("The full-screen viewer still mints the ORIGINAL")
    func viewerLoadsOriginal() async throws {
        let spy = FetchSpy()
        let blobs = blobs()

        _ = await resolver(spy).location(for: media(blobs), canReact: true)
        #expect(spy.calls == [blobs.original])
    }

    // MARK: - Cell -

    @Test("A bubble draws a copy cached under its DISPLAY rendition without minting")
    func cellDrawsTheDerivedCopy() async throws {
        let spy = FetchSpy()
        let blobs = blobs()
        let media = media(blobs)
        let load = try load(media)
        _ = await cacheOnDiskOnly(blobs.display, processor: load.processor)

        let remote = resolver(spy).location(for: media, canReact: true, drawing: load) { _ in }
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true), maxWidth: 240, localImage: nil, remote: remote)

        let drawn = await drawnImage { cell.imageView }
        #expect(drawn?.cgImage?.width == 7)
        #expect(spy.calls.isEmpty)
    }

    @Test("A bubble draws a photo cached under its ORIGINAL before the update, without minting")
    func cellDrawsTheOriginalCopy() async throws {
        let spy = FetchSpy()
        let blobs = blobs()
        let media = media(blobs)
        let load = try load(media)
        _ = await cacheOnDiskOnly(blobs.original, processor: load.processor)

        let remote = resolver(spy).location(for: media, canReact: true, drawing: load) { _ in }
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true), maxWidth: 240, localImage: nil, remote: remote)

        let drawn = await drawnImage { cell.imageView }
        #expect(drawn?.cgImage?.width == 7)
        #expect(spy.calls.isEmpty)
    }

    @Test("A cached derived copy that won't read is the one evicted, so the reload mints instead of looping")
    func cellEvictsTheCopyItDrew() async throws {
        let blobs = blobs()
        let media = media(blobs)
        let load = try load(media)
        // Bytes that don't decode, on disk where the drawn copy's key points: Kingfisher files a
        // processed copy under `key@identifier`.
        let key = ChatMediaImageSource.cacheKey(for: blobs.display)
        try caches.images.diskStorage.store(value: Data("not an image".utf8), forKey: "\(key)@\(load.processor.identifier)")
        #expect(ChatMediaImageSource.isCached(blobID: blobs.display, processor: load.processor, in: caches))

        let remote = try #require(resolver(FetchSpy()).location(for: media, canReact: true, drawing: load) { _ in })
        #expect(remote.rendition == display(blobs))
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        var reloads = 0
        cell.onReload = { reloads += 1 }
        cell.configure(with: ChatMessage(id: "1", content: .media(media), sender: .other, canReact: true), maxWidth: 240, localImage: nil, remote: remote)

        for _ in 0..<200 where reloads == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(reloads == 1)
        #expect(!ChatMediaImageSource.isCached(blobID: blobs.display, processor: load.processor, in: caches))
    }

    // MARK: - Load report -

    @Test("A bubble's load report names the copy it loaded")
    func reportNamesTheRendition() {
        let error = KingfisherError.requestError(reason: .emptyRequest)
        #expect(ChatMediaLoadReport(.failure(error), blobID: nil, surface: .bubble, rendition: .display).metadata["rendition"] == "display")
        #expect(ChatMediaLoadReport(.failure(error), blobID: nil, surface: .bubble, rendition: .thumbnail).metadata["rendition"] == "thumbnail")
    }

    @Test("A load that doesn't know its copy logs no rendition rather than guessing")
    func reportOmitsAnUnknownRendition() {
        let error = KingfisherError.requestError(reason: .emptyRequest)
        #expect(ChatMediaLoadReport(.failure(error), blobID: nil, surface: .quote, rendition: nil).metadata["rendition"] == nil)
    }

    // MARK: - Mapping -

    private let me = UUID()
    private let them = UUID()

    private func photoMessage(_ attachment: MediaAttachment, id: UInt64 = 1) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: them,
            content: .media([attachment], caption: nil),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: id, eventSequence: id
        )
    }

    private func attachment(_ blobs: Blobs) -> MediaAttachment {
        MediaAttachment(blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, renditions: [display(blobs), thumbnail(blobs)])
    }

    private func messages(_ messages: [ConversationMessage]) -> [ChatMessage] {
        let byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        return ChatItem.from(
            messages,
            selfUserID: me,
            cashBranding: { _ in ("Cash", nil) },
            counterpartName: "Ada",
            quotedMessage: { byID[$0] }
        ).compactMap { item in
            if case .message(let message) = item { return message } else { return nil }
        }
    }

    @Test("A photo row carries the copies the server derived")
    func rowCarriesRenditions() throws {
        let blobs = blobs()
        let row = try #require(messages([photoMessage(attachment(blobs))]).first)
        guard case .media(let media) = row.content else {
            Issue.record("expected a photo row, got \(row.content)")
            return
        }
        #expect(media.renditions == [display(blobs), thumbnail(blobs)])
    }

    @Test("A reply to a photo quotes its THUMBNAIL")
    func quoteUsesTheThumbnail() throws {
        let blobs = blobs()
        let reply = ConversationMessage(
            id: MessageID(value: 2), senderID: me, content: .text("nice"),
            date: Date(timeIntervalSince1970: 1_700_000_010), unreadSeq: 2, eventSequence: 2,
            repliedTo: MessageID(value: 1)
        )
        let quote = try #require(messages([photoMessage(attachment(blobs)), reply]).compactMap(\.quote).first)
        #expect(quote.kind == .media(thumbnailBlobID: blobs.thumbnail, sealed: nil))
    }

    @Test("The composer's reply strip shows the photo's THUMBNAIL")
    func replyStripUsesTheThumbnail() {
        let blobs = blobs()
        let preview = ConversationScreen.replyPreview(
            for: photoMessage(attachment(blobs)),
            display: DisplayCurrency(currency: .usd, rates: [Rate]())
        ) { _ in "Cash" }
        #expect(preview.kind == .media(thumbnailBlobID: blobs.thumbnail, sealed: nil))
    }
}
