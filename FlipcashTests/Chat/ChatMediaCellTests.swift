//
//  ChatMediaCellTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI
import Kingfisher

@Suite("Chat photo cell")
@MainActor
struct ChatMediaCellTests {

    private static let blurhash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
    private static let remoteURL = URL(string: "https://example.com/a.jpg")!
    private static let pill = ReactionPill(emoji: "🔥", count: 1, selfReacted: false, pending: false)

    private func media(caption: String? = nil, isRedacted: Bool = false, blurhash: String? = Self.blurhash) -> ChatMediaContent {
        ChatMediaContent(
            blobID: BlobID(data: Data([1])),
            width: 1179,
            height: 2556,
            blurhash: blurhash,
            caption: caption,
            isRedacted: isRedacted
        )
    }

    private func configuredCell(
        _ media: ChatMediaContent,
        canReact: Bool = true,
        localImage: UIImage? = nil,
        remoteURL: URL? = nil
    ) -> ChatMediaCell {
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media), sender: .other, reactions: [Self.pill], canReact: canReact),
            maxWidth: 240,
            localImage: localImage,
            remote: remoteURL.map { ChatMediaLocation(url: $0) }
        )
        return cell
    }

    private func outgoing(id: String = "1", receipt: ChatReceipt? = nil) -> ChatMessage {
        ChatMessage(id: id, content: .media(media()), sender: .me, receipt: receipt)
    }

    // MARK: - Send progress -

    @Test("A row with no send progress draws no overlay")
    func noProgressNoOverlay() {
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: nil, remote: nil)
        #expect(!cell.progressOverlay.isShowing)
        #expect(cell.progressOverlay.isHidden)
    }

    @Test("An uploading photo shows its share of bytes sent; processing shows a full, indeterminate bar")
    func overlayFollowsProgress() async {
        let progress = ChatPhotoSendProgress()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: progress, remote: nil)
        #expect(cell.progressOverlay.isShowing)
        #expect(cell.progressOverlay.fraction == 0)
        #expect(!cell.progressOverlay.isIndeterminate)

        progress.didUpload(BlobUploadProgress(sentBytes: 40, totalBytes: 100))
        await waitFor { cell.progressOverlay.fraction == 0.4 }
        #expect(cell.progressOverlay.fraction == 0.4)

        progress.beginProcessing()
        await waitFor { cell.progressOverlay.isIndeterminate }
        #expect(cell.progressOverlay.fraction == 1)
        #expect(cell.progressOverlay.isIndeterminate)
        #expect(cell.progressOverlay.isShowing)
    }

    @Test("The overlay hides once the photo is sent")
    func overlayHidesWhenSent() async {
        let progress = ChatPhotoSendProgress()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: progress, remote: nil)
        progress.beginSending()

        progress.finish()
        await waitFor { !cell.progressOverlay.isShowing }
        #expect(!cell.progressOverlay.isShowing)
    }

    @Test("The confirmed row, reconfigured without progress, hides the overlay")
    func overlayHidesWhenConfirmedRowLosesProgress() {
        let progress = ChatPhotoSendProgress()
        progress.beginSending()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: progress, remote: nil)
        #expect(cell.progressOverlay.isShowing)

        cell.configure(with: outgoing(receipt: .delivered), maxWidth: 240, localImage: nil, progress: nil, remote: nil)
        #expect(!cell.progressOverlay.isShowing)
    }

    @Test("A failed row hides the overlay for the failed receipt, and a retry brings it back")
    func failedRowHidesOverlay() async {
        let progress = ChatPhotoSendProgress()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: progress, remote: nil)

        progress.fail()
        cell.configure(with: outgoing(receipt: .failed("Not delivered")), maxWidth: 240, localImage: nil, progress: progress, remote: nil)
        #expect(!cell.progressOverlay.isShowing)
        #expect(cell.progressOverlay.isHidden)

        progress.beginAttempt()
        cell.configure(with: outgoing(), maxWidth: 240, localImage: nil, progress: progress, remote: nil)
        #expect(cell.progressOverlay.isShowing)
    }

    @Test("A recycled cell drops the previous row's progress")
    func recycledCellIgnoresOldProgress() async {
        let old = ChatPhotoSendProgress()
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(with: outgoing(id: "old"), maxWidth: 240, localImage: nil, progress: old, remote: nil)
        cell.prepareForReuse()
        cell.configure(with: outgoing(id: "new", receipt: .delivered), maxWidth: 240, localImage: nil, progress: nil, remote: nil)

        old.didUpload(BlobUploadProgress(sentBytes: 50, totalBytes: 100))
        for _ in 0..<5 { await Task.yield() }
        #expect(!cell.progressOverlay.isShowing)
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() { await Task.yield() }
    }

    @Test("A row with no image yet draws its BlurHash")
    func drawsBlurhashBeforeImageLoads() {
        let cell = configuredCell(media())
        #expect(cell.imageView.image != nil)
    }

    @Test("A pending row draws the staged local image")
    func drawsLocalImage() {
        let image = UIImage(systemName: "photo")!
        let cell = configuredCell(media(), localImage: image)
        #expect(cell.imageView.image === image)
    }

    @Test("A caption shows as its own bubble")
    func showsCaption() {
        let cell = configuredCell(media(caption: "hi"))
        #expect(cell.captionBubble.isHidden == false)
        #expect(cell.captionLabel.text == "hi")
    }

    @Test("A nil or empty caption hides the caption bubble", arguments: [nil, ""] as [String?])
    func hidesEmptyCaption(caption: String?) {
        let cell = configuredCell(media(caption: caption))
        #expect(cell.captionBubble.isHidden)
    }

    // MARK: - Reply quote -

    private static let quote = ChatQuote(stableID: "7", authorName: "Ada", snippet: "dinner at 7?", kind: .text)

    @Test("A photo sent as a reply shows the quote over it")
    func reply_showsQuote() {
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media()), sender: .me, quote: Self.quote),
            maxWidth: 240,
            localImage: nil,
            remote: nil
        )
        #expect(cell.quotePanel.isHidden == false)
    }

    @Test("A photo that is not a reply hides the quote")
    func plain_hidesQuote() {
        let cell = configuredCell(media())
        #expect(cell.quotePanel.isHidden)
    }

    @Test("A recycled cell drops the previous row's quote")
    func reuse_dropsQuote() {
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media()), sender: .me, quote: Self.quote),
            maxWidth: 240,
            localImage: nil,
            remote: nil
        )
        cell.configure(with: outgoing(id: "2"), maxWidth: 240, localImage: nil, remote: nil)
        #expect(cell.quotePanel.isHidden)
    }

    @Test("A long quote stays inside the photo, within its width cap")
    func longQuote_staysInsidePhoto() {
        let long = ChatQuote(stableID: "7", authorName: "Ada", snippet: String(repeating: "wide ", count: 40), kind: .text)
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media()), sender: .other, quote: long),
            maxWidth: 240,
            localImage: nil,
            remote: nil
        )
        cell.contentView.frame = cell.bounds
        cell.layoutIfNeeded()

        let photo = cell.imageView.convert(cell.imageView.bounds, to: cell)
        let quote = cell.quotePanel.convert(cell.quotePanel.bounds, to: cell)
        #expect(quote.width > 0)
        #expect(photo.insetBy(dx: -0.5, dy: -0.5).contains(quote))
        #expect(quote.width <= photo.width * ChatMediaCell.quoteMaxWidthFraction + 0.5)
        #expect(abs(quote.minX - photo.minX - ChatMediaCell.quoteInset) < 0.5)
        #expect(abs(quote.minY - photo.minY - ChatMediaCell.quoteInset) < 0.5)
    }

    @Test("The quote's corners are concentric with the photo's, floored at the grouped radius")
    func quoteCorners_concentricWithPhoto() {
        let rounded = ChatQuotePanelView.photoOverlayRadii(photoTopLeading: BubbleBackgroundView.baseRadius, inset: 4)
        #expect(rounded.topLeading == 8)
        #expect(rounded.topTrailing == 8)
        #expect(rounded.bottomLeading == 8)
        #expect(rounded.bottomTrailing == 8)

        let flattened = ChatQuotePanelView.photoOverlayRadii(photoTopLeading: BubbleBackgroundView.groupedRadius, inset: 4)
        #expect(flattened.topLeading == BubbleBackgroundView.groupedRadius)
        #expect(flattened.topTrailing == 8)
    }

    @Test("The quote reports the row it jumps to")
    func quote_reportsItsTarget() {
        var tapped: String?
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media()), sender: .other, quote: Self.quote),
            maxWidth: 240,
            localImage: nil,
            remote: nil
        )
        cell.onQuoteTap = { tapped = $0 }
        cell.quotePanel.simulateTap()
        #expect(tapped == "7")
    }

    @Test("A viewable row shows its reactions and takes a tap")
    func viewableRow() {
        let cell = configuredCell(media(), remoteURL: Self.remoteURL)
        #expect(!cell.blurhashOnly)
        #expect(!cell.reactionRow.isHidden)
        #expect(cell.imageTap.isEnabled)
    }

    @Test("A redacted row draws only its BlurHash, even handed a URL")
    func redactedRowIsBlurhashOnly() {
        let local = UIImage(systemName: "photo")!
        let cell = configuredCell(media(isRedacted: true), localImage: local, remoteURL: Self.remoteURL)
        #expect(cell.blurhashOnly)
        #expect(cell.reactionRow.isHidden)
        #expect(!cell.imageTap.isEnabled)
        #expect(cell.imageView.image != nil)
        #expect(cell.imageView.image !== local)
    }

    @Test("A previewer's row draws only its BlurHash")
    func previewingRowIsBlurhashOnly() {
        let cell = configuredCell(media(), canReact: false)
        #expect(cell.blurhashOnly)
        #expect(cell.reactionRow.isHidden)
        #expect(!cell.imageTap.isEnabled)
    }

    @Test("A photo caches under its blob, so a freshly signed URL reuses the download")
    func cachesUnderBlob() {
        let blobID = BlobID(data: Data([1]))
        let first = ChatMediaImageSource.source(blobID: blobID, location: ChatMediaLocation(url: URL(string: "https://cdn.example.com/a.jpg?sig=1")!))
        let second = ChatMediaImageSource.source(blobID: blobID, location: ChatMediaLocation(url: URL(string: "https://cdn.example.com/a.jpg?sig=2")!))
        let other = ChatMediaImageSource.source(blobID: BlobID(data: Data([2])), location: ChatMediaLocation(url: URL(string: "https://cdn.example.com/a.jpg?sig=1")!))

        #expect(first.cacheKey == second.cacheKey)
        #expect(first.cacheKey != other.cacheKey)
        #expect(second.url?.absoluteString.hasSuffix("sig=2") == true)
    }

    @Test("An encrypted photo caches under the same blob key and loads through a decrypting provider")
    func encryptedPhotoCachesUnderBlob() {
        let blobID = BlobID(data: Data([1]))
        let url = URL(string: "https://cdn.example.com/a.bin?sig=1")!
        let plain = ChatMediaImageSource.source(blobID: blobID, location: ChatMediaLocation(url: url))
        let sealed = ChatMediaImageSource.source(blobID: blobID, location: ChatMediaLocation(url: url) { $0 })

        #expect(sealed.cacheKey == plain.cacheKey)
        guard case .provider = sealed else {
            Issue.record("An encrypted photo must load through a provider, not straight from the network")
            return
        }
    }

    @Test("A downloaded photo persists to disk, so it survives a memory trim or relaunch")
    func persistsDownloadToDisk() async {
        let key = "chat-media-test-\(UUID().uuidString)"
        let processor = DownsamplingImageProcessor(size: CGSize(width: 40, height: 40))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }

        await withCheckedContinuation { continuation in
            ChatMediaImageSource.persist(image, cacheType: .none, forKey: key, processor: processor) {
                continuation.resume()
            }
        }

        let cache = ChatMediaImageSource.cache
        cache.clearMemoryCache()
        #expect(cache.imageCachedType(forKey: key, processorIdentifier: processor.identifier) == .disk)
        try? await cache.removeImage(forKey: key, processorIdentifier: processor.identifier)
    }

    @Test("A photo already served from a cache is not written again")
    func skipsCachedHits() async {
        let key = "chat-media-test-\(UUID().uuidString)"
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }

        ChatMediaImageSource.persist(image, cacheType: .memory, forKey: key, processor: nil)

        #expect(!ChatMediaImageSource.cache.imageCachedType(forKey: key).cached)
    }

    // MARK: - Encrypted -

    /// A cell drawing an encrypted photo whose blob is a local file and whose decryption is `decrypt`.
    private func encryptedCell(decrypt: @escaping @Sendable (Data) throws -> Data) throws -> ChatMediaCell {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-media-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: file)
        let media = ChatMediaContent(
            blobID: BlobID(data: Data(UUID().uuidString.utf8)),
            width: 100,
            height: 100,
            blurhash: Self.blurhash,
            caption: nil,
            isRedacted: false,
            sealed: SealedBlob(senderID: UUID(), plaintextSize: 3)
        )
        let cell = ChatMediaCell(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cell.configure(
            with: ChatMessage(id: "1", content: .media(media), sender: .other, reactions: [], canReact: true),
            maxWidth: 240,
            localImage: nil,
            remote: ChatMediaLocation(url: file, decrypt: decrypt)
        )
        return cell
    }

    private func waitForUnavailable(_ cell: ChatMediaCell) async {
        for _ in 0..<200 where cell.unavailableLabel.isHidden {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("An encrypted photo that fails to authenticate keeps its BlurHash, says it can't be shown, and takes no tap")
    func undecryptablePhotoShowsUnavailable() async throws {
        let cell = try encryptedCell { _ in throw BlobOpenFailure.authentication }
        #expect(cell.unavailableLabel.isHidden)

        await waitForUnavailable(cell)

        #expect(!cell.unavailableLabel.isHidden)
        #expect(!cell.imageTap.isEnabled)
        #expect(cell.imageView.image != nil)
    }

    @Test("An encrypted photo whose plaintext doesn't decode as an image says it can't be shown")
    func undecodablePhotoShowsUnavailable() async throws {
        let cell = try encryptedCell { $0 }

        await waitForUnavailable(cell)

        #expect(!cell.unavailableLabel.isHidden)
    }

    @Test("Only a blob that will never open counts as undecryptable; a failed fetch stays retryable")
    func undecryptableClassification() {
        func providerError(_ underlying: any Error) -> KingfisherError {
            .imageSettingError(reason: .dataProviderError(provider: RawImageDataProvider(data: Data(), cacheKey: "k"), error: underlying))
        }
        #expect(ChatMediaImageSource.isUndecryptable(providerError(BlobOpenFailure.authentication)))
        #expect(ChatMediaImageSource.isUndecryptable(providerError(BlobOpenFailure.length)))
        #expect(ChatMediaImageSource.isUndecryptable(providerError(BlobOpenFailure.undecodable)))
        #expect(!ChatMediaImageSource.isUndecryptable(providerError(URLError(.notConnectedToInternet))))
    }
}
