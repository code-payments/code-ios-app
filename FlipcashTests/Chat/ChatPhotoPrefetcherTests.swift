//
//  ChatPhotoPrefetcherTests.swift
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
import FlipcashStore

/// A photo that arrives on the live stream is downloaded into the cache its bubble draws from, so
/// opening the chat draws it without a mint or a download.
@Suite("Chat photo prefetch")
@MainActor
struct ChatPhotoPrefetcherTests {

    @MainActor
    private final class Spy {
        var mints: [BlobID] = []
        var downloads: [URL] = []
        var fetches: [BlobID] = []
    }

    private let me = UUID()
    private let them = UUID()
    private let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
    private let screen = ChatPhotoPrefetcher.Screen(rowWidth: 393, scale: 3)
    private static let wifi = ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false)
    /// A signed URL, so a test can check the log never carries it.
    private static let link = BlobDownloadLink(url: URL(string: "https://cdn.example.com/blob?Signature=secret-signature")!)

    nonisolated private static let photoData: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 9, height: 12), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 9, height: 12))
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

    private func attachment(_ blobs: Blobs, sealed: SealedBlob? = nil) -> MediaAttachment {
        MediaAttachment(
            blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, sealed: sealed,
            renditions: sealed == nil ? [
                MediaRendition(role: .display, blobID: blobs.display, width: 1080, height: 1440),
                MediaRendition(role: .thumbnail, blobID: blobs.thumbnail, width: 120, height: 160),
            ] : []
        )
    }

    private func photoMessage(_ attachment: MediaAttachment, id: UInt64 = 1, from sender: UUID? = nil, redacted: Bool = false) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender ?? them,
            content: .media([attachment], caption: nil),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: id, eventSequence: id,
            redacted: redacted
        )
    }

    private func prefetcher(
        _ spy: Spy,
        network: ChatPhotoPrefetchNetwork = Self.wifi,
        muted: Bool = false,
        decrypt: ChatMediaURLResolver.BlobDecrypt? = nil,
        status: Int = 200,
        body: Data = Self.photoData
    ) -> ChatPhotoPrefetcher {
        ChatPhotoPrefetcher(
            selfUserID: me,
            mint: { blobID, _ in
                spy.mints.append(blobID)
                return Self.link
            },
            decrypt: { _ in decrypt },
            network: { network },
            isMuted: { _ in muted },
            screen: { screen },
            download: { url, _ in
                await MainActor.run { spy.downloads.append(url) }
                return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
            },
            cache: ChatMediaImageSource.cache
        )
    }

    /// The row the transcript builds for `message`.
    private func row(_ message: ConversationMessage, group: Bool = false) throws -> ChatMessage {
        let rows = ChatItem.from(
            [message],
            selfUserID: me,
            cashBranding: { _ in ("Cash", nil) },
            counterpartName: "Ada",
            quotedMessage: { _ in nil },
            namesAuthors: group
        ).compactMap { item -> ChatMessage? in
            if case .message(let message) = item { return message } else { return nil }
        }
        return try #require(rows.first)
    }

    /// The load the transcript's bubble makes for `row`, as `ChatViewController.configure` builds it.
    private func bubbleLoad(_ row: ChatMessage) throws -> (media: ChatMediaContent, load: ChatMediaBubbleLoad, maxWidth: CGFloat) {
        guard case .media(let media) = row.content else {
            Issue.record("expected a photo row, got \(row.content)")
            throw CancellationError()
        }
        let maxWidth = ChatPhotoBubbleLayout.maxWidth(
            rowWidth: screen.rowWidth,
            attributedIncoming: row.isAttributedTranscript && row.sender != .me
        )
        return (media, try #require(ChatMediaBubbleLoad(media: media, maxWidth: maxWidth, scale: screen.scale)), maxWidth)
    }

    private func remove(_ blobIDs: [BlobID]) async {
        for blobID in blobIDs {
            await ChatMediaImageSource.evict(blobID: blobID, processor: DefaultImageProcessor.default)
        }
    }

    // MARK: - Same copy as the bubble -

    @Test("A prefetch picks the copy and processor the bubble will, in a DM and a group",
          arguments: [false, true])
    func sameLoadAsTheBubble(group: Bool) throws {
        let message = photoMessage(attachment(blobs()))
        let bubble = try bubbleLoad(try row(message, group: group)).load
        let prefetch = try #require(ChatMediaBubbleLoad(
            attachment: attachment(blobs()), redacted: false,
            rowWidth: screen.rowWidth, attributedIncoming: group, scale: screen.scale
        ))
        // Fresh blobs on each side, so compare by role and size; the processor keys the draw.
        #expect(prefetch.rendition.role == bubble.rendition.role)
        #expect(prefetch.rendition.width == bubble.rendition.width)
        #expect(prefetch.processor.identifier == bubble.processor.identifier)
    }

    @Test("The prefetch's copy is the very blob the bubble asks for")
    func sameBlobAsTheBubble() throws {
        let attachment = attachment(blobs())
        let bubble = try bubbleLoad(try row(photoMessage(attachment))).load
        let prefetch = try #require(ChatMediaBubbleLoad(
            attachment: attachment, redacted: false,
            rowWidth: screen.rowWidth, attributedIncoming: false, scale: screen.scale
        ))
        #expect(prefetch.rendition == bubble.rendition)
        #expect(prefetch.rendition.role == .display)
    }

    // MARK: - The bubble draws from it -

    @Test("After a prefetch the bubble draws from disk with no mint, alone or fronting a stack")
    func bubbleDrawsThePrefetch() async throws {
        let spy = Spy()
        let blobs = blobs()
        let message = photoMessage(attachment(blobs))
        defer { Task { await remove([blobs.display]) } }

        let report = try #require(await prefetcher(spy).prefetch(message, in: conversationID, isGroup: false, trigger: .stream))
        #expect(report.outcome == .downloaded)
        #expect(spy.mints == [blobs.display])
        // Nothing in memory: the bubble has to find the copy on disk, as after a relaunch.
        #expect(ChatMediaImageSource.cache.imageCachedType(forKey: ChatMediaImageSource.cacheKey(for: blobs.display)) == .disk)

        let bubble = try bubbleLoad(try row(message))
        let stacked = ChatMediaCell.processor(
            for: ChatMediaContent(
                blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, caption: nil, isRedacted: false,
                stackPhotos: [
                    ChatMediaStackPhoto(messageID: "a", blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, isRedacted: false, sealed: nil, canReply: true, canForward: true),
                    ChatMediaStackPhoto(messageID: "b", blobID: uniqueBlobID(), width: 3024, height: 4032, blurhash: nil, isRedacted: false, sealed: nil, canReply: true, canForward: true),
                ],
                renditions: bubble.media.renditions
            ),
            maxWidth: bubble.maxWidth
        )
        #expect(stacked.identifier != bubble.load.processor.identifier)

        for processor in [bubble.load.processor, stacked] {
            let resolver = ChatMediaURLResolver(fetch: { blobID in
                spy.fetches.append(blobID)
                return nil
            })
            let load = ChatMediaBubbleLoad(rendition: bubble.load.rendition, processor: processor)
            let location = try #require(resolver.location(for: bubble.media, canReact: true, drawing: load) { _ in })
            #expect(location.url == nil)
            #expect(location.rendition == bubble.load.rendition)

            let source = ChatMediaImageSource.source(blobID: location.rendition?.blobID, location: location)
            let result = await ChatMediaImageSource.retrieve(source, options: ChatMediaImageSource.options(processor: processor))
            #expect((try? result.get().image) != nil)
            // The draw cached its downsampled copy in memory; drop it so the next processor reads disk.
            ChatMediaImageSource.cache.clearMemoryCache()
        }
        #expect(spy.fetches.isEmpty)
    }

    @Test("A sealed photo is decrypted before it is cached, and keeps its ORIGINAL for Save")
    func sealedPhoto() async throws {
        let spy = Spy()
        let blobs = blobs()
        let ciphertext = Data("sealed".utf8)
        let message = photoMessage(attachment(blobs, sealed: SealedBlob(senderID: them, plaintextSize: Self.photoData.count)))
        defer { Task { await remove([blobs.original]) } }

        let prefetcher = prefetcher(spy, decrypt: { blob, _, _ in
            #expect(blob == ciphertext)
            return Self.photoData
        }, body: ciphertext)
        let report = try #require(await prefetcher.prefetch(message, in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .downloaded)
        #expect(report.rendition == .original)
        #expect(report.decrypt != nil)
        #expect(spy.mints == [blobs.original])
        #expect(ChatMediaImageSource.cache.imageCachedType(forKey: ChatMediaImageSource.cacheKey(for: blobs.original)) == .disk)
        #expect(ChatMediaImageSource.originalData(blobID: blobs.original) == Self.photoData)
    }

    @Test("A sealed photo waits for its chat's key rather than downloading what it can't open")
    func sealedWithoutKey() async throws {
        let spy = Spy()
        let message = photoMessage(attachment(blobs(), sealed: SealedBlob(senderID: them, plaintextSize: 10)))
        let report = try #require(await prefetcher(spy).prefetch(message, in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .skipped(.keyPending))
        #expect(spy.mints.isEmpty)
    }

    // MARK: - Skips -

    @Test("Policy skips download nothing", arguments: [
        ChatPhotoPrefetchSkip.own, .redacted, .muted, .offline, .lowDataMode,
    ])
    func policySkip(expected: ChatPhotoPrefetchSkip) async throws {
        let spy = Spy()
        let message = photoMessage(attachment(blobs()), from: expected == .own ? me : them, redacted: expected == .redacted)
        let network: ChatPhotoPrefetchNetwork = switch expected {
        case .offline: ChatPhotoPrefetchNetwork(connected: false, constrained: false, expensive: false)
        case .lowDataMode: ChatPhotoPrefetchNetwork(connected: true, constrained: true, expensive: true)
        default: Self.wifi
        }
        let prefetcher = prefetcher(spy, network: network, muted: expected == .muted)
        let report = try #require(await prefetcher.prefetch(message, in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .skipped(.policy(expected)))
        #expect(spy.mints.isEmpty)
        #expect(spy.downloads.isEmpty)
    }

    @Test("Cellular and roaming still prefetch")
    func expensiveNetwork() async throws {
        let spy = Spy()
        let blobs = blobs()
        defer { Task { await remove([blobs.display]) } }
        let cellular = ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: true)
        let report = try #require(await prefetcher(spy, network: cellular).prefetch(photoMessage(attachment(blobs)), in: conversationID, isGroup: false, trigger: .stream))
        #expect(report.outcome == .downloaded)
    }

    @Test("A photo already cached under its ORIGINAL is not downloaded again")
    func cachedUnderOriginal() async throws {
        let spy = Spy()
        let blobs = blobs()
        try ChatMediaImageSource.storeFullSize(Self.photoData, blobID: blobs.original, in: ChatMediaImageSource.cache)
        defer { Task { await remove([blobs.original]) } }

        let report = try #require(await prefetcher(spy).prefetch(photoMessage(attachment(blobs)), in: conversationID, isGroup: false, trigger: .stream))
        #expect(report.outcome == .skipped(.policy(.cached)))
        #expect(spy.mints.isEmpty)
    }

    // MARK: - Failures leave no trace -

    @Test("A refused download caches nothing and logs the status, never the URL")
    func refusedDownload() async throws {
        let spy = Spy()
        let blobs = blobs()
        let report = try #require(await prefetcher(spy, status: 403).prefetch(photoMessage(attachment(blobs)), in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .failed(.fetch))
        #expect(report.metadata["status"] == "403")
        #expect(!ChatMediaImageSource.isCached(blobID: blobs.display, processor: DefaultImageProcessor.default))
        #expect(!report.metadata.values.contains { "\($0)".contains("secret-signature") })
    }

    @Test("Bytes that aren't an image are not cached")
    func notAnImage() async throws {
        let spy = Spy()
        let blobs = blobs()
        let report = try #require(await prefetcher(spy, body: Data("<html>".utf8)).prefetch(photoMessage(attachment(blobs)), in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .failed(.decode))
        #expect(!ChatMediaImageSource.isCached(blobID: blobs.display, processor: DefaultImageProcessor.default))
    }

    @Test("A failed transfer logs its error domain and code, never its description")
    func transferError() async throws {
        let blobs = blobs()
        let prefetcher = ChatPhotoPrefetcher(
            selfUserID: me,
            mint: { _, _ in Self.link },
            decrypt: { _ in nil },
            network: { Self.wifi },
            isMuted: { _ in false },
            screen: { screen },
            download: { url, _ in throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: url]) },
            cache: ChatMediaImageSource.cache
        )
        let report = try #require(await prefetcher.prefetch(photoMessage(attachment(blobs)), in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .failed(.fetch))
        #expect(report.metadata["errorDomain"] == "\(NSURLErrorDomain)")
        #expect(report.metadata["errorCode"] == "\(URLError.timedOut.rawValue)")
        #expect(!report.metadata.values.contains { "\($0)".contains("secret-signature") })
    }

    // MARK: - Arrivals -

    @Test("Only photos newer than what was stored before the batch are considered")
    func onlyArrivals() async throws {
        let spy = Spy()
        let old = blobs()
        let new = blobs()
        defer { Task { await remove([new.display]) } }
        let tasks = prefetcher(spy).handleLive(
            [photoMessage(attachment(old), id: 4), photoMessage(attachment(new), id: 5)],
            in: conversationID,
            isGroup: false,
            countedThrough: MessageID(value: 4)
        )
        #expect(tasks.count == 1)
        for task in tasks { _ = await task.value }
        #expect(spy.mints == [new.display])
    }
}

/// The conversation controller hands each live batch to the prefetcher.
@Suite("Chat photo prefetch wiring")
@MainActor
struct ChatPhotoPrefetchWiringTests {

    @MainActor
    private final class Minted {
        var blobIDs: [BlobID] = []
    }

    private func photo(id: UInt64, from sender: UserID, display: BlobID) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: sender,
            content: .media([MediaAttachment(
                blobID: BlobID(data: Data(UUID().uuidString.utf8)), width: 3024, height: 4032, blurhash: nil,
                renditions: [MediaRendition(role: .display, blobID: display, width: 1080, height: 1440)]
            )], caption: nil),
            date: Date(timeIntervalSince1970: TimeInterval(id)), unreadSeq: id, eventSequence: id
        )
    }

    @Test("A photo from someone else that arrives live is prefetched; one of the user's own is not")
    func livePhotoReachesThePrefetcher() async throws {
        let (database, url) = try Database.makeTemp()
        defer { Database.removeTemp(at: url) }
        let me = UUID(), them = UUID()
        let mock = MockConversations()
        let controller = ConversationController(
            fetching: mock, membership: mock, viewerSettings: mock, messaging: mock, streaming: mock,
            contactNaming: MockDMContactNaming(),
            database: database,
            owner: .generate()!, selfUserID: me
        )
        let minted = Minted()
        controller.photoPrefetcher = ChatPhotoPrefetcher(
            selfUserID: me,
            mint: { blobID, _ in
                minted.blobIDs.append(blobID)
                return nil
            },
            decrypt: { _ in nil },
            network: { ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false) },
            isMuted: { _ in false },
            screen: { ChatPhotoPrefetcher.Screen(rowWidth: 393, scale: 3) }
        )
        let theirs = BlobID(data: Data(UUID().uuidString.utf8))
        let mine = BlobID(data: Data(UUID().uuidString.utf8))

        controller.start()
        try await waitUntil { mock.streamOpened }
        mock.emit(.sent([photo(id: 1, from: me, display: mine), photo(id: 2, from: them, display: theirs)], in: .test(1)))
        try await waitUntil { !minted.blobIDs.isEmpty }
        try await Task.sleep(for: .milliseconds(100))

        #expect(minted.blobIDs == [theirs])
        controller.stop()
    }
}
