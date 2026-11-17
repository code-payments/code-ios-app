//
//  ChatPhotoPushPrefetcher.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import CoreGraphics
import ImageIO

/// Downloads the photo of a pushed chat message from the notification extension, into
/// ``BlobCache/chatPhotos``, so the bubble draws without a URL mint or a CDN download when the
/// chat opens.
///
/// The photo takes the copy its bubble will ask for (``ChatPhotoBubbleLayout/rendition(of:rowWidth:attributedIncoming:scale:)``)
/// and lands under that copy's blob ID. A sealed photo lands decrypted, under its ORIGINAL's ID.
/// Which photos are worth the data is ``ChatPhotoPrefetch/skip(own:redacted:muted:cached:network:)``,
/// the same rules as the in-app prefetch.
///
/// The extension has about 24 MB of memory, so a plaintext copy goes to disk without being read
/// into memory, and a copy whose size the server doesn't send, or that is over the limit for its
/// kind, is skipped. A sealed copy is read and decrypted in memory, ciphertext and plaintext at
/// once, so its limit is lower. A failure leaves nothing in the store.
public struct ChatPhotoPushPrefetcher: Sendable {

    /// Mints a download URL for a blob in the pushed message's chat.
    public typealias Mint = @Sendable (BlobID) async throws -> BlobDownloadLink?
    /// Decrypts a sealed blob's downloaded bytes.
    public typealias Decrypt = @Sendable (Data, BlobID, SealedBlob) throws -> Data
    /// Builds the chat's decryption, or nil while its key can't be opened here.
    public typealias FetchDecrypt = @Sendable () async -> Decrypt?
    /// Downloads a URL's body to a file the caller then owns, with the transfer's timings.
    typealias Download = @Sendable (URL) async throws -> (file: URL, response: URLResponse, transfer: ChatMediaTransfer?)

    /// The largest plaintext copy the extension downloads.
    public static let plaintextLimitBytes: Int64 = 8 * 1024 * 1024
    /// The largest sealed copy the extension downloads.
    public static let sealedLimitBytes: Int64 = 3 * 1024 * 1024

    private let store: BlobCache
    private let mint: Mint
    private let download: Download
    private let plaintextLimit: Int64
    private let sealedLimit: Int64

    public init(mint: @escaping Mint) {
        self.init(store: .chatPhotos, mint: mint, download: Self.urlSessionDownload)
    }

    init(
        store: BlobCache,
        mint: @escaping Mint,
        download: @escaping Download,
        plaintextLimit: Int64 = Self.plaintextLimitBytes,
        sealedLimit: Int64 = Self.sealedLimitBytes
    ) {
        self.store = store
        self.mint = mint
        self.download = download
        self.plaintextLimit = plaintextLimit
        self.sealedLimit = sealedLimit
    }

    /// Downloads `message`'s photo, or decides not to, and logs which. Nil for a message that
    /// carries no photo with a blob. `isGroup` is whether the chat names its authors, which narrows
    /// a member's bubble; `muted` is the push's own mute flag.
    @discardableResult
    public func prefetch(
        _ message: ConversationMessage,
        selfUserID: UserID,
        isGroup: Bool,
        muted: Bool,
        network: ChatPhotoPrefetchNetwork,
        rowWidth: CGFloat,
        scale: CGFloat,
        decrypt fetchDecrypt: FetchDecrypt
    ) async -> ChatPhotoPrefetchReport? {
        guard case .media(let attachments, _) = message.content, let attachment = attachments.first else { return nil }
        let own = message.senderID == selfUserID
        guard let rendition = ChatPhotoBubbleLayout.rendition(
            of: attachment,
            rowWidth: rowWidth,
            attributedIncoming: isGroup && !own,
            scale: scale
        ) else { return nil }

        var report = ChatPhotoPrefetchReport(trigger: .push, blobID: rendition.blobID, rendition: rendition.role, outcome: .downloaded)
        report.sealed = attachment.sealed != nil
        defer { report.log() }

        let stored = store.holds(rendition.blobID) || attachment.blobID.map(store.holds) ?? false
        if let skip = ChatPhotoPrefetch.skip(
            own: own,
            redacted: message.redacted,
            muted: muted,
            cached: stored,
            network: network
        ) {
            report.outcome = .skipped(.policy(skip))
            return report
        }

        var decrypt: Decrypt?
        if attachment.sealed != nil {
            decrypt = await fetchDecrypt()
            guard decrypt != nil else {
                report.outcome = .skipped(.keyPending)
                return report
            }
        }

        await run(rendition, sealed: attachment.sealed, decrypt: decrypt, into: &report)
        return report
    }

    /// Mints, downloads, opens and stores `rendition`, recording each step into `report`.
    private func run(
        _ rendition: MediaRendition,
        sealed: SealedBlob?,
        decrypt: Decrypt?,
        into report: inout ChatPhotoPrefetchReport
    ) async {
        let clock = ContinuousClock()
        let started = clock.now
        defer { report.total = clock.now - started }

        let link: BlobDownloadLink?
        do {
            link = try await mint(rendition.blobID)
        } catch {
            report.fail(.mint, error)
            return
        }
        report.mint = clock.now - started
        guard let link else {
            report.outcome = .failed(.mint)
            return
        }

        let limit = sealed == nil ? plaintextLimit : sealedLimit
        guard let size = link.sizeBytes else {
            report.outcome = .skipped(.noSize)
            return
        }
        guard size <= limit else {
            report.outcome = .skipped(.tooLarge)
            return
        }

        let file: URL
        do {
            let downloaded = try await download(link.url)
            file = downloaded.file
            var transfer = downloaded.transfer ?? ChatMediaTransfer()
            if let response = downloaded.response as? HTTPURLResponse {
                transfer.record(response)
            }
            report.transfer = transfer
            if let status = transfer.status, !(200..<300).contains(status) {
                try? FileManager.default.removeItem(at: file)
                report.outcome = .failed(.fetch)
                return
            }
        } catch {
            report.fail(.fetch, error)
            return
        }
        // Whatever happens below, the downloaded file doesn't outlive this call.
        defer { try? FileManager.default.removeItem(at: file) }

        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        report.bytes = bytes
        guard Int64(bytes) <= limit else {
            report.outcome = .skipped(.tooLarge)
            return
        }

        if let sealed, let decrypt {
            let ciphertext: Data
            do {
                ciphertext = try Data(contentsOf: file)
            } catch {
                report.fail(.fetch, error)
                return
            }
            let image: Data
            let start = clock.now
            do {
                image = try decrypt(ciphertext, rendition.blobID, sealed)
            } catch {
                report.fail(.decrypt, error)
                return
            }
            report.decrypt = clock.now - start
            guard Self.isImage(CGImageSourceCreateWithData(image as CFData, nil)) else {
                report.outcome = .failed(.decode)
                return
            }
            store.write(image, for: rendition.blobID)
            if !store.holds(rendition.blobID) {
                report.outcome = .failed(.store)
            }
        } else {
            guard Self.isImage(CGImageSourceCreateWithURL(file as CFURL, nil)) else {
                report.outcome = .failed(.decode)
                return
            }
            if !store.moveIn(file, for: rendition.blobID) {
                report.outcome = .failed(.store)
            }
        }
    }

    /// Whether `source` reads as an image, checked without decoding it.
    private static func isImage(_ source: CGImageSource?) -> Bool {
        guard let source else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// A session that never downloads over Low Data Mode, even when the path the extension read
    /// first was out of date.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.allowsConstrainedNetworkAccess = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private static let urlSessionDownload: Download = { url in
        let metrics = TransferMetrics()
        let (file, response) = try await session.download(from: url, delegate: metrics)
        return (file, response, metrics.transfer)
    }
}

/// Collects a download's timings for its log line.
private final class TransferMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: ChatMediaTransfer?

    var transfer: ChatMediaTransfer? { lock.withLock { collected } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let transfer = ChatMediaTransfer(metrics: metrics)
        lock.withLock { collected = transfer }
    }
}
