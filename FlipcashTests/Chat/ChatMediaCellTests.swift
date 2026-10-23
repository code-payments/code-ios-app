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

    private func captionText(_ cell: ChatMediaCell) -> LinkTextView? {
        cell.captionBubble.descendants(of: LinkTextView.self).first
    }

    @Test("A caption shows as its own bubble")
    func showsCaption() {
        let cell = configuredCell(media(caption: "hi"))
        #expect(cell.captionBubble.isHidden == false)
        #expect(captionText(cell)?.text == "hi")
    }

    @Test("A caption's mentions are drawn as pills on the caption's pill layer")
    func captionDrawsMentionPills() throws {
        let caption = "Any idea @jeff @mcansh?"
        let mentions = MentionDetector.mentions(in: caption, excluding: [])
        let cell = configuredCell(ChatMediaContent(
            blobID: BlobID(data: Data([1])), width: 1179, height: 2556, blurhash: Self.blurhash,
            caption: caption, captionPreview: LinkPreview(links: [], mentions: mentions), isRedacted: false
        ))
        cell.layoutIfNeeded()

        #expect(mentions.count == 2)
        let text = try #require(captionText(cell))
        let layer = try #require(text.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        let path = try #require(layer.path)
        #expect(!path.boundingBoxOfPath.isEmpty)
        #expect(text.mentionPillRects.count == 2)
    }

    @Test("A caption with no mentions draws no pills")
    func plainCaptionDrawsNoPills() throws {
        let cell = configuredCell(media(caption: "just words"))
        cell.layoutIfNeeded()
        let text = try #require(captionText(cell))
        let layer = try #require(text.layer.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
        #expect(layer.path?.boundingBoxOfPath.isEmpty ?? true)
    }

    @Test("A nil or empty caption hides the caption bubble", arguments: [nil, ""] as [String?])
    func hidesEmptyCaption(caption: String?) {
        let cell = configuredCell(media(caption: caption))
        #expect(cell.captionBubble.isHidden)
    }

    private final class StubTap: UITapGestureRecognizer {
        var point: CGPoint = .zero
        override func location(in view: UIView?) -> CGPoint { point }
    }

    private static let linkURL = URL(string: "https://apple.com/mac")!

    private func captionWithLink() -> ChatMediaCell {
        let url = Self.linkURL
        let caption = "look https://apple.com/mac"
        let link = DetectedLink(range: NSRange(location: 5, length: 21), url: url)
        let preview = LinkPreview(links: [link])
        let cell = configuredCell(ChatMediaContent(
            blobID: BlobID(data: Data([1])), width: 1179, height: 2556, blurhash: Self.blurhash,
            caption: caption, captionPreview: preview, isRedacted: false
        ))
        cell.layoutIfNeeded()
        return cell
    }

    @Test("A link in a caption is underlined and a tap on it fires the open-URL handler")
    func captionLinkTapOpensURL() throws {
        let cell = captionWithLink()
        var opened: [URL] = []
        cell.onOpenURL = { opened.append($0) }

        let text = try #require(captionText(cell))
        #expect(text.attributedText.attribute(.link, at: 6, effectiveRange: nil) as? URL == Self.linkURL)

        let start = try #require(text.position(from: text.beginningOfDocument, offset: 8))
        let end = try #require(text.position(from: start, offset: 1))
        let rect = text.firstRect(for: try #require(text.textRange(from: start, to: end)))
        let tap = StubTap()
        tap.point = CGPoint(x: rect.midX, y: rect.midY)
        cell.captionBubble.perform(NSSelectorFromString("spanTapped:"), with: tap)
        #expect(opened == [Self.linkURL])

        tap.point = CGPoint(x: rect.midX, y: rect.midY + 400)
        cell.captionBubble.perform(NSSelectorFromString("spanTapped:"), with: tap)
        #expect(opened == [Self.linkURL])
    }

    @Test("A caption with only a plain link shows no card")
    func captionWithoutCardHidesCard() {
        let cell = captionWithLink()
        #expect(cell.captionBubble.cardView.isHidden)
    }

    // MARK: - Bare card and emoji captions -

    private static let cashLink = "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"

    private func cashCaptionCell() -> (ChatMediaCell, LinkCard) {
        let url = URL(string: Self.cashLink)!
        let range = NSRange(location: 0, length: (Self.cashLink as NSString).length)
        let card = LinkCard.cash(LinkCard.Cash(url: url, entropy: "KNi8pQr1n5hRU65vKJGge3", range: range))
        let cell = configuredCell(ChatMediaContent(
            blobID: BlobID(data: Data([1])), width: 1179, height: 2556, blurhash: Self.blurhash,
            caption: Self.cashLink,
            captionPreview: LinkPreview(links: [DetectedLink(range: range, url: url)], card: card),
            isRedacted: false
        ))
        cell.layoutIfNeeded()
        return (cell, card)
    }

    @Test("A caption that is a Flipcash link draws the text path's bare card under the photo, with no bubble")
    func captionDrawsBareCard() {
        let (cell, _) = cashCaptionCell()
        #expect(!cell.captionBubble.isHidden)
        #expect(cell.captionBubble.isBare)
        #expect(!cell.captionBubble.cardView.isHidden)
        #expect(cell.captionEmoji.isHidden)
        #expect(cell.captionBubble.frame.minY >= cell.imageView.convert(cell.imageView.bounds, to: cell.captionBubble.superview).maxY)
    }

    @Test("A tap on the caption's card reports the card the way a text row's does")
    func captionCardTapFires() {
        let (cell, card) = cashCaptionCell()
        var taps: [LinkCard] = []
        cell.onLinkCardTap = { taps.append($0) }
        cell.captionBubble.cardTapped()
        #expect(taps == [card])
    }

    private static let groupLink = "https://app.flipcash.com/chat/06d26e5c-a399-8983-98ea-e59785db34a0"

    @Test("A caption split around a Flipcash card draws its words, then the card, under the photo")
    func captionSplitDrawsWordsThenCard() {
        let url = URL(string: Self.groupLink)!
        let range = NSRange(location: 0, length: (Self.groupLink as NSString).length)
        let card = LinkCard.group(LinkCard.Group(url: url, chatID: ConversationID(data: Data(repeating: 7, count: 32)), range: range))
        let cell = configuredCell(ChatMediaContent(
            blobID: BlobID(data: Data([1])), width: 1179, height: 2556, blurhash: Self.blurhash,
            caption: "join us \(Self.groupLink)",
            captionRows: [
                ChatMediaCaptionRow(kind: .leadingText, text: "join us", preview: nil),
                ChatMediaCaptionRow(kind: .card, text: Self.groupLink, preview: LinkPreview(links: [DetectedLink(range: range, url: url)], card: card)),
            ],
            isRedacted: false
        ))
        cell.layoutIfNeeded()
        #expect(!cell.captionBubble.isHidden)
        #expect(!cell.captionBubble.isBare)
        #expect(!cell.captionCardBubble.isHidden)
        #expect(cell.captionCardBubble.isBare)
        #expect(cell.captionTrailingBubble.isHidden)
        #expect(captionText(cell)?.text == "join us")
        let photoBottom = cell.imageView.convert(cell.imageView.bounds, to: cell.captionBubble.superview).maxY
        #expect(cell.captionBubble.frame.minY >= photoBottom)
        #expect(cell.captionCardBubble.frame.minY >= cell.captionBubble.frame.maxY)

        var taps: [LinkCard] = []
        cell.onLinkCardTap = { taps.append($0) }
        cell.captionCardBubble.cardTapped()
        #expect(taps == [card])
    }

    @Test("An emoji-only caption draws as the text path's bare enlarged emoji, with no bubble")
    func captionDrawsBareEmoji() {
        let cell = configuredCell(media(caption: "🔥🔥"))
        cell.layoutIfNeeded()
        #expect(cell.captionBubble.isHidden)
        #expect(!cell.captionEmoji.isHidden)
        #expect(cell.captionEmoji.maskingPath == nil)
        #expect(cell.captionEmoji.descendants(of: UILabel.self).contains { $0.text == "🔥🔥" && $0.font.pointSize == 48 })
    }

    @Test("A caption with words keeps the bubble and hides the emoji view; a recycled cell drops the emoji")
    func wordsCaptionHidesEmoji() {
        let cell = configuredCell(media(caption: "🔥🔥"))
        cell.prepareForReuse()
        #expect(cell.captionEmoji.isHidden)
        let words = configuredCell(media(caption: "nice 🔥"))
        #expect(!words.captionBubble.isHidden)
        #expect(words.captionEmoji.isHidden)
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
