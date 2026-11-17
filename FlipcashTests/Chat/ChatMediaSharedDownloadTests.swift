//
//  ChatMediaSharedDownloadTests.swift
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

/// A photo that arrives in the open chat is wanted twice at once: by the stream's prefetch and by
/// its bubble. Whichever starts first downloads it, and the other waits for that download instead
/// of starting its own.
@Suite("Chat photo shared download", .timeLimit(.minutes(1)))
@MainActor
struct ChatMediaSharedDownloadTests {

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
    private final class Spy {
        var mints: [BlobID] = []
        var downloads: [URL] = []
        var resolverMints: [BlobID] = []
        var reloads = 0
    }

    private let me = UUID()
    private let them = UUID()
    private let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
    private let screen = ChatPhotoPrefetcher.Screen(rowWidth: 393, scale: 3)

    // MARK: - The bubble waits for a prefetch -

    @Test("A bubble configured while its photo prefetches waits, then draws the prefetched copy")
    func bubbleWaitsForPrefetch() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let spy = Spy()
        let photo = try photo()
        let prefetcher = prefetcher(spy, port: port, download: Self.fromServer(failing: false))
        let prefetch = Task { await prefetcher.prefetch(photo.message, in: conversationID, isGroup: false, trigger: .stream) }
        await server.waitForRequests(1)

        let resolver = ChatMediaURLResolver(fetch: { blobID in
            spy.resolverMints.append(blobID)
            return BlobDownloadLink(url: Self.url(port))
        }, caches: caches, pushedPhotos: pushed)
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.onReload = { [weak cell] in
            spy.reloads += 1
            let location = resolver.location(for: photo.media, canReact: true, drawing: photo.load) { _ in }
            cell?.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: location)
        }
        cell.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: urlLocation(photo, port: port))
        #expect(cell.imageView.kf.taskIdentifier == nil)

        server.release()
        let report = try #require(await prefetch.value)
        #expect(report.outcome == .downloaded)
        try await Self.untilDrawn(cell)

        #expect(spy.reloads == 1)
        #expect(server.requestCount == 1)
        #expect(spy.resolverMints.isEmpty)
        #expect(cell.imageView.image != nil)
    }

    @Test("A bubble waiting on a prefetch that fails downloads the photo itself, once")
    func bubbleDownloadsAfterFailedPrefetch() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let spy = Spy()
        let photo = try photo()
        let prefetcher = prefetcher(spy, port: port, download: Self.fromServer(failing: true))
        let prefetch = Task { await prefetcher.prefetch(photo.message, in: conversationID, isGroup: false, trigger: .stream) }
        await server.waitForRequests(1)

        // The resolver hands the reloaded row the URL it minted for the first configure.
        let location = urlLocation(photo, port: port)
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.onReload = { [weak cell] in
            spy.reloads += 1
            cell?.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: location)
        }
        cell.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: location)
        #expect(cell.imageView.kf.taskIdentifier == nil)

        server.release()
        let report = try #require(await prefetch.value)
        #expect(report.outcome == .failed(.fetch))
        try await Self.untilDrawn(cell)

        #expect(spy.reloads == 1)
        #expect(server.requestCount == 2)
        #expect(cell.imageView.image != nil)
    }

    // MARK: - The prefetch waits for a bubble -

    @Test("A prefetch of a photo its bubble is downloading skips it without a mint")
    func prefetchSkipsBubbleDownload() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let spy = Spy()
        let photo = try photo()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: urlLocation(photo, port: port))
        await server.waitForRequests(1)

        let report = try #require(await prefetcher(spy, port: port, download: Self.instant(spy))
            .prefetch(photo.message, in: conversationID, isGroup: false, trigger: .stream))
        #expect(report.outcome == .skipped(.inFlight))
        #expect(spy.mints.isEmpty)
        #expect(spy.downloads.isEmpty)

        server.release()
        try await Self.untilDrawn(cell)
        #expect(server.requestCount == 1)
        #expect(cell.imageView.image != nil)
    }

    @Test("A bubble recycled mid-download leaves its photo free for the next prefetch")
    func recycledBubbleFreesPhoto() async throws {
        let server = try LoopbackPhotoServer(holding: true)
        let port = try await server.start()
        defer { server.stop() }
        let spy = Spy()
        let photo = try photo()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: photo.row, maxWidth: photo.maxWidth, localImage: nil, remote: urlLocation(photo, port: port))
        await server.waitForRequests(1)
        cell.prepareForReuse()
        try await Self.untilLoaded(cell)

        let report = try #require(await prefetcher(spy, port: port, download: Self.instant(spy))
            .prefetch(photo.message, in: conversationID, isGroup: false, trigger: .stream))
        #expect(report.outcome == .downloaded)
        #expect(spy.mints == [photo.load.rendition.blobID])
    }

    // MARK: - Claims -

    @Test("A claim released late leaves a newer claim on its key held")
    func lateReleaseKeepsNewerClaim() throws {
        let downloads = ChatMediaDownloads()
        let first = try #require(downloads.claim("photo"))
        #expect(downloads.claim("photo") == nil)
        downloads.release(first)

        let second = try #require(downloads.claim("photo"))
        downloads.release(first)
        #expect(downloads.claim("photo") == nil)
        downloads.release(second)
        #expect(downloads.claim("photo") != nil)
    }

    @Test("Everyone waiting on a key is called once, when its download ends")
    func waitersCalledOnce() throws {
        let downloads = ChatMediaDownloads()
        var calls = 0
        #expect(!downloads.whenFinished("photo") { calls += 1 })

        let claim = try #require(downloads.claim("photo"))
        #expect(downloads.whenFinished("photo") { calls += 1 })
        #expect(downloads.whenFinished("photo") { calls += 1 })
        #expect(calls == 0)
        downloads.release(claim)
        #expect(calls == 2)
        downloads.release(claim)
        #expect(calls == 2)
    }

    // MARK: - Helpers -

    /// One incoming photo with renditions, and the row and bubble load the transcript builds for it.
    private struct Photo {
        let message: ConversationMessage
        let row: ChatMessage
        let media: ChatMediaContent
        let load: ChatMediaBubbleLoad
        let maxWidth: CGFloat
    }

    private func photo() throws -> Photo {
        func blob() -> BlobID { BlobID(data: Data(UUID().uuidString.utf8)) }
        let attachment = MediaAttachment(
            blobID: blob(), width: 3024, height: 4032, blurhash: nil, sealed: nil,
            renditions: [
                MediaRendition(role: .display, blobID: blob(), width: 1080, height: 1440),
                MediaRendition(role: .thumbnail, blobID: blob(), width: 120, height: 160),
            ]
        )
        let message = ConversationMessage(
            id: MessageID(value: 1), senderID: them,
            content: .media([attachment], caption: nil),
            date: Date(timeIntervalSince1970: 1_700_000_000), unreadSeq: 1, eventSequence: 1,
            redacted: false
        )
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
        let load = try #require(ChatMediaBubbleLoad(media: media, maxWidth: maxWidth, scale: screen.scale))
        return Photo(message: message, row: row, media: media, load: load, maxWidth: maxWidth)
    }

    /// The location the resolver hands a bubble for `photo`'s copy once it has minted a URL.
    private func urlLocation(_ photo: Photo, port: UInt16) -> ChatMediaLocation {
        ChatMediaLocation(url: Self.url(port), caches: caches, rendition: photo.load.rendition)
    }

    private func prefetcher(_ spy: Spy, port: UInt16, download: @escaping ChatPhotoPrefetcher.Download) -> ChatPhotoPrefetcher {
        ChatPhotoPrefetcher(
            selfUserID: me,
            mint: { blobID, _ in
                spy.mints.append(blobID)
                return BlobDownloadLink(url: Self.url(port))
            },
            decrypt: { _ in nil },
            network: { ChatPhotoPrefetchNetwork(connected: true, constrained: false, expensive: false) },
            isMuted: { _ in false },
            screen: { screen },
            download: download,
            caches: caches,
            pushedPhotos: pushed
        )
    }

    nonisolated private static func url(_ port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)/photo.png?Signature=1")!
    }

    /// No cache between the prefetch and the server, so every prefetch download reaches it.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Downloads from the loopback server, so the server's hold also holds the prefetch. `failing`
    /// throws once the server answers, as a connection dropped mid-transfer would.
    nonisolated private static func fromServer(failing: Bool) -> ChatPhotoPrefetcher.Download {
        { url, _ in
            let downloaded = try await session.data(from: url)
            if failing { throw URLError(.networkConnectionLost) }
            return downloaded
        }
    }

    /// Answers at once without the network, recording each download.
    nonisolated private static func instant(_ spy: Spy) -> ChatPhotoPrefetcher.Download {
        { url, _ in
            await MainActor.run { spy.downloads.append(url) }
            return (photoData, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    nonisolated private static let photoData: Data = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 9, height: 12), format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 9, height: 12))
        }
    }()

    /// Kingfisher sets a downloaded image a run loop after it clears the view's task, when its fade
    /// starts, so a test of what the row drew waits for the image itself.
    private static func untilDrawn(_ cell: ChatMediaCell) async throws {
        while cell.imageView.image == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Kingfisher clears the view's task once its load finishes or is cancelled, so this returns
    /// either way; the suite's time limit only catches a load that never ends.
    private static func untilLoaded(_ cell: ChatMediaCell) async throws {
        while cell.imageView.kf.taskIdentifier != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
