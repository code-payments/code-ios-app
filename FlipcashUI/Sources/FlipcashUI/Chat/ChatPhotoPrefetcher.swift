//
//  ChatPhotoPrefetcher.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import ImageIO
import FlipcashCore
import Kingfisher

nonisolated private let logger = Logger(label: "flipcash.chat-media")

/// Downloads a photo when its message arrives, so the bubble draws from the cache when the chat
/// opens instead of waiting on a URL mint and a CDN download.
///
/// Each photo takes the copy its bubble will ask for (``ChatMediaBubbleLoad/init(attachment:redacted:rowWidth:attributedIncoming:scale:)``)
/// and lands as that copy's full-size bytes in the chat-media disk cache, under the key the bubble
/// probes. Which photos are worth the data is ``ChatPhotoPrefetch/skip(own:redacted:muted:cached:network:)``.
/// A prefetch that fails leaves nothing behind: the bubble loads the photo as it would have.
@MainActor
public final class ChatPhotoPrefetcher {

    /// Mints a download URL for a blob in a chat.
    public typealias Mint = @MainActor (BlobID, ConversationID) async throws -> BlobDownloadLink?
    /// Builds a chat's blob decryption, or nil while its key is unknown.
    public typealias FetchDecrypt = @MainActor (ConversationID) async -> ChatMediaURLResolver.BlobDecrypt?
    /// Downloads a URL's body, reporting its timings to the trace.
    typealias Download = @Sendable (URL, ChatMediaLoadTrace) async throws -> (Data, URLResponse)

    /// The width and scale of the screen a transcript would draw on.
    public struct Screen: Sendable {
        public let rowWidth: CGFloat
        public let scale: CGFloat

        public init(rowWidth: CGFloat, scale: CGFloat) {
            self.rowWidth = rowWidth
            self.scale = scale
        }
    }

    private let selfUserID: UserID
    private let mint: Mint
    private let fetchDecrypt: FetchDecrypt
    private let network: () -> ChatPhotoPrefetchNetwork
    private let isMuted: (ConversationID) -> Bool
    private let screen: () -> Screen
    private let download: Download
    private let caches: ChatMediaCaches
    /// Where the notification extension leaves the photos it downloaded for a push.
    private let pushedPhotos: BlobCache
    /// The blobs being downloaded, so a photo that arrives twice downloads once.
    private var inFlight: Set<BlobID> = []

    public convenience init(
        selfUserID: UserID,
        mint: @escaping Mint,
        decrypt: @escaping FetchDecrypt,
        network: @escaping () -> ChatPhotoPrefetchNetwork,
        isMuted: @escaping (ConversationID) -> Bool,
        screen: @escaping () -> Screen
    ) {
        self.init(
            selfUserID: selfUserID, mint: mint, decrypt: decrypt, network: network, isMuted: isMuted,
            screen: screen, download: Self.urlSessionDownload, caches: .shared, pushedPhotos: .chatPhotos
        )
    }

    init(
        selfUserID: UserID,
        mint: @escaping Mint,
        decrypt: @escaping FetchDecrypt,
        network: @escaping () -> ChatPhotoPrefetchNetwork,
        isMuted: @escaping (ConversationID) -> Bool,
        screen: @escaping () -> Screen,
        download: @escaping Download,
        caches: ChatMediaCaches,
        pushedPhotos: BlobCache
    ) {
        self.selfUserID = selfUserID
        self.mint = mint
        self.fetchDecrypt = decrypt
        self.network = network
        self.isMuted = isMuted
        self.screen = screen
        self.download = download
        self.caches = caches
        self.pushedPhotos = pushedPhotos
    }

    /// Considers messages that reached the client as live stream events. `countedThrough` is the
    /// newest message stored before this batch: anything at or below it is a replay or an edit of a
    /// message already seen, not an arrival. `isGroup` is whether the chat names its authors, which
    /// narrows a member's bubble.
    @discardableResult
    public func handleLive(
        _ messages: [ConversationMessage],
        in conversationID: ConversationID,
        isGroup: Bool,
        countedThrough: MessageID?
    ) -> [Task<ChatPhotoPrefetchReport?, Never>] {
        messages.compactMap { message in
            if let countedThrough, message.id <= countedThrough { return nil }
            guard case .media = message.content else { return nil }
            return Task { await self.prefetch(message, in: conversationID, isGroup: isGroup, trigger: .stream) }
        }
    }

    /// Downloads `message`'s photo, or decides not to, and logs which. Nil for a message that
    /// carries no photo with a blob.
    func prefetch(
        _ message: ConversationMessage,
        in conversationID: ConversationID,
        isGroup: Bool,
        trigger: ChatPhotoPrefetchTrigger
    ) async -> ChatPhotoPrefetchReport? {
        guard case .media(let attachments, _) = message.content, let attachment = attachments.first else { return nil }
        let own = message.senderID == selfUserID
        let screen = screen()
        guard let load = ChatMediaBubbleLoad(
            attachment: attachment,
            redacted: message.redacted,
            rowWidth: screen.rowWidth,
            attributedIncoming: isGroup && !own,
            scale: screen.scale
        ) else { return nil }

        let rendition = load.rendition
        var report = ChatPhotoPrefetchReport(trigger: trigger, blobID: rendition.blobID, rendition: rendition.role, outcome: .downloaded)
        report.sealed = attachment.sealed != nil
        defer { report.log() }

        // Either copy the bubble probes, in the chat cache or left there by the notification extension.
        let cached = [rendition.blobID, attachment.blobID].compactMap(\.self).contains {
            ChatMediaImageSource.isCached(blobID: $0, processor: load.processor, in: caches) || pushedPhotos.holds($0)
        }
        if let skip = ChatPhotoPrefetch.skip(
            own: own,
            redacted: message.redacted,
            muted: isMuted(conversationID),
            cached: cached,
            network: network()
        ) {
            report.outcome = .skipped(.policy(skip))
            return report
        }

        var decrypt: ChatMediaURLResolver.BlobDecrypt?
        if attachment.sealed != nil {
            decrypt = await fetchDecrypt(conversationID)
            guard decrypt != nil else {
                report.outcome = .skipped(.keyPending)
                return report
            }
        }

        guard inFlight.insert(rendition.blobID).inserted else {
            report.outcome = .skipped(.inFlight)
            return report
        }
        defer { inFlight.remove(rendition.blobID) }

        await run(rendition, of: attachment, in: conversationID, decrypt: decrypt, into: &report)
        return report
    }

    /// Mints, downloads, opens and stores `rendition`, recording each step into `report`.
    private func run(
        _ rendition: MediaRendition,
        of attachment: MediaAttachment,
        in conversationID: ConversationID,
        decrypt: ChatMediaURLResolver.BlobDecrypt?,
        into report: inout ChatPhotoPrefetchReport
    ) async {
        let clock = ContinuousClock()
        let started = clock.now
        defer { report.total = clock.now - started }

        let link: BlobDownloadLink?
        do {
            link = try await mint(rendition.blobID, conversationID)
        } catch {
            report.fail(.mint, error)
            return
        }
        report.mint = clock.now - started
        guard let link else {
            report.outcome = .failed(.mint)
            return
        }

        let trace = ChatMediaLoadTrace()
        let body: Data
        do {
            let (data, response) = try await download(link.url, trace)
            report.transfer = trace.snapshot.transfer
            if let response = response as? HTTPURLResponse {
                var transfer = report.transfer ?? ChatMediaTransfer()
                transfer.record(response)
                report.transfer = transfer
                guard (200..<300).contains(response.statusCode) else {
                    report.outcome = .failed(.fetch)
                    return
                }
            }
            body = data
        } catch {
            report.transfer = trace.snapshot.transfer
            report.fail(.fetch, error)
            return
        }
        report.bytes = body.count

        let blobID = rendition.blobID
        let sealed = attachment.sealed
        let caches = self.caches
        let opened: Result<Duration?, ChatPhotoPrefetchReport.Failure> = await Task.detached {
            var image = body
            var decrypted: Duration?
            if let decrypt, let sealed {
                let start = ContinuousClock.now
                do {
                    image = try decrypt(body, blobID, sealed)
                } catch {
                    return .failure(.init(step: .decrypt, error: error))
                }
                decrypted = ContinuousClock.now - start
                ChatMediaImageSource.storeOriginal(image, forKey: ChatMediaImageSource.cacheKey(for: blobID), in: caches)
            }
            guard Self.isImage(image) else { return .failure(.init(step: .decode, error: nil)) }
            do {
                try ChatMediaImageSource.storeFullSize(image, blobID: blobID, in: caches.images)
            } catch {
                return .failure(.init(step: .store, error: error))
            }
            return .success(decrypted)
        }.value
        switch opened {
        case .success(let decrypted):
            report.decrypt = decrypted
        case .failure(let failure):
            report.fail(failure.step, failure.error)
        }
    }

    /// Whether `data` holds an image ImageIO can read, checked without decoding it.
    nonisolated private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// A session that never downloads over Low Data Mode, even before the app reads the path.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: configuration)
    }()

    private static let urlSessionDownload: Download = { url, trace in
        try await session.data(from: url, delegate: trace)
    }
}
