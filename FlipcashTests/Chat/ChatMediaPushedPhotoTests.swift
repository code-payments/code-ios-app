//
//  ChatMediaPushedPhotoTests.swift
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

/// The notification extension downloads a pushed photo into ``BlobCache/chatPhotos``. The bubble
/// reads that store before it mints, so a photo that arrived by push draws without a mint or a
/// download.
@Suite("Chat photos downloaded by the notification extension")
@MainActor
struct ChatMediaPushedPhotoTests {

    @MainActor
    private final class Spy {
        var fetches: [BlobID] = []
        var mints: [BlobID] = []
    }

    private let me = UUID()
    private let them = UUID()
    private let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
    private let screen = ChatPhotoPrefetcher.Screen(rowWidth: 393, scale: 3)
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

    private struct Blobs {
        let original: BlobID
        let display: BlobID
        let thumbnail: BlobID
    }

    /// Blobs no other test touches, since the chat cache is shared and on disk.
    private func blobs() -> Blobs {
        func unique() -> BlobID { BlobID(data: Data(UUID().uuidString.utf8)) }
        return Blobs(original: unique(), display: unique(), thumbnail: unique())
    }

    /// An empty store in its own directory, standing in for the App Group's.
    private func pushedStore() -> BlobCache {
        BlobCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("PushedPhotos-\(UUID().uuidString)"),
            limitBytes: 32 * 1024 * 1024
        )
    }

    private func photoMessage(_ blobs: Blobs, sealed: SealedBlob? = nil) -> ConversationMessage {
        let attachment = MediaAttachment(
            blobID: blobs.original, width: 3024, height: 4032, blurhash: nil, sealed: sealed,
            renditions: sealed == nil ? [
                MediaRendition(role: .display, blobID: blobs.display, width: 1080, height: 1440),
                MediaRendition(role: .thumbnail, blobID: blobs.thumbnail, width: 120, height: 160),
            ] : []
        )
        return ConversationMessage(
            id: MessageID(value: 1), senderID: them,
            content: .media([attachment], caption: nil),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: 1, eventSequence: 1,
            redacted: false
        )
    }

    /// The photo and load the transcript's bubble makes for `message`, as `ChatViewController.configure` builds it.
    private func bubble(_ message: ConversationMessage) throws -> (media: ChatMediaContent, load: ChatMediaBubbleLoad) {
        let rows = ChatItem.from(
            [message],
            selfUserID: me,
            cashBranding: { _ in ("Cash", nil) },
            counterpartName: "Ada",
            quotedMessage: { _ in nil },
            namesAuthors: false
        ).compactMap { item -> ChatMessage? in
            if case .message(let message) = item { return message } else { return nil }
        }
        let row = try #require(rows.first)
        guard case .media(let media) = row.content else {
            Issue.record("expected a photo row, got \(row.content)")
            throw CancellationError()
        }
        let maxWidth = ChatPhotoBubbleLayout.maxWidth(rowWidth: screen.rowWidth, attributedIncoming: false)
        return (media, try #require(ChatMediaBubbleLoad(media: media, maxWidth: maxWidth, scale: screen.scale)))
    }

    private func resolver(_ spy: Spy, pushed: BlobCache, link: BlobDownloadLink? = nil) -> ChatMediaURLResolver {
        ChatMediaURLResolver(
            fetch: { blobID in
                spy.fetches.append(blobID)
                return link
            },
            pushedPhotos: pushed
        )
    }

    /// Where the bubble draws from, waiting on whatever the resolver waits on.
    private func location(_ resolver: ChatMediaURLResolver, _ media: ChatMediaContent, _ load: ChatMediaBubbleLoad) async -> ChatMediaLocation? {
        await withCheckedContinuation { continuation in
            var resumed = false
            let immediate = resolver.location(for: media, canReact: true, drawing: load) { location in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: location)
            }
            if let immediate, !resumed {
                resumed = true
                continuation.resume(returning: immediate)
            }
        }
    }

    private func remove(_ blobIDs: [BlobID]) async {
        for blobID in blobIDs {
            await ChatMediaImageSource.evict(blobID: blobID, processor: DefaultImageProcessor.default)
        }
    }

    // MARK: - The bubble -

    @Test("A photo the extension downloaded draws with no mint, and moves into the chat cache")
    func drawsThePushedRendition() async throws {
        let spy = Spy()
        let blobs = blobs()
        let pushed = pushedStore()
        defer { Task { await remove([blobs.display]) } }
        let (media, load) = try bubble(photoMessage(blobs))
        #expect(load.rendition.blobID == blobs.display)
        pushed.write(Self.photoData, for: blobs.display)

        let location = try #require(await location(resolver(spy, pushed: pushed), media, load))

        #expect(location.url == nil)
        #expect(location.rendition == load.rendition)
        #expect(spy.fetches.isEmpty)
        #expect(ChatMediaImageSource.isCached(blobID: blobs.display, processor: load.processor))
        #expect(!pushed.holds(blobs.display))

        // The bubble's own draw, from disk as after a relaunch, still with no network.
        ChatMediaImageSource.cache.clearMemoryCache()
        let source = ChatMediaImageSource.source(blobID: location.rendition?.blobID, location: location)
        let result = await ChatMediaImageSource.retrieve(source, options: ChatMediaImageSource.options(processor: load.processor))
        #expect((try? result.get().image) != nil)
        #expect(spy.fetches.isEmpty)
    }

    @Test("A pushed ORIGINAL draws when the bubble asks for a rendition")
    func drawsThePushedOriginal() async throws {
        let spy = Spy()
        let blobs = blobs()
        let pushed = pushedStore()
        defer { Task { await remove([blobs.original]) } }
        let (media, load) = try bubble(photoMessage(blobs))
        pushed.write(Self.photoData, for: blobs.original)

        let location = try #require(await location(resolver(spy, pushed: pushed), media, load))

        #expect(location.url == nil)
        #expect(location.rendition?.role == .original)
        #expect(location.rendition?.blobID == blobs.original)
        #expect(spy.fetches.isEmpty)
        #expect(ChatMediaImageSource.isCached(blobID: blobs.original, processor: load.processor))
    }

    @Test("A pushed sealed photo draws with no mint and keeps its bytes for Save")
    func sealedPushedPhoto() async throws {
        let spy = Spy()
        let blobs = blobs()
        let pushed = pushedStore()
        defer { Task { await remove([blobs.original]) } }
        let (media, load) = try bubble(photoMessage(blobs, sealed: SealedBlob(senderID: them, plaintextSize: Self.photoData.count)))
        #expect(load.rendition.role == .original)
        // The extension decrypts before it stores, so the store holds the photo as sent.
        pushed.write(Self.photoData, for: blobs.original)

        let location = try #require(await location(resolver(spy, pushed: pushed), media, load))

        #expect(location.url == nil)
        #expect(spy.fetches.isEmpty)
        #expect(ChatMediaImageSource.originalData(blobID: blobs.original) == Self.photoData)
    }

    @Test("With nothing pushed, the bubble mints its rendition")
    func mintsWithNothingPushed() async throws {
        let spy = Spy()
        let blobs = blobs()
        let (media, load) = try bubble(photoMessage(blobs))

        let location = try #require(await location(resolver(spy, pushed: pushedStore(), link: Self.link), media, load))

        #expect(location.url == Self.link.url)
        #expect(spy.fetches == [blobs.display])
    }

    // MARK: - The in-app prefetch -

    @Test("A photo the extension already downloaded is not downloaded again on arrival")
    func prefetchSkipsAPushedPhoto() async throws {
        let spy = Spy()
        let blobs = blobs()
        let pushed = pushedStore()
        pushed.write(Self.photoData, for: blobs.display)
        let prefetcher = ChatPhotoPrefetcher(
            selfUserID: me,
            mint: { blobID, _ in
                spy.mints.append(blobID)
                return Self.link
            },
            decrypt: { _ in nil },
            network: { ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false) },
            isMuted: { _ in false },
            screen: { screen },
            download: { url, _ in
                (Self.photoData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            cache: ChatMediaImageSource.cache,
            pushedPhotos: pushed
        )

        let report = try #require(await prefetcher.prefetch(photoMessage(blobs), in: conversationID, isGroup: false, trigger: .stream))

        #expect(report.outcome == .skipped(.policy(.cached)))
        #expect(spy.mints.isEmpty)
    }
}
