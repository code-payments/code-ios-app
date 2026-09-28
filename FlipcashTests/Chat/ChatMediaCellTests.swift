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
            remoteURL: remoteURL
        )
        return cell
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
        let first = ChatMediaImageSource.resource(blobID: blobID, url: URL(string: "https://cdn.example.com/a.jpg?sig=1")!)
        let second = ChatMediaImageSource.resource(blobID: blobID, url: URL(string: "https://cdn.example.com/a.jpg?sig=2")!)
        let other = ChatMediaImageSource.resource(blobID: BlobID(data: Data([2])), url: URL(string: "https://cdn.example.com/a.jpg?sig=1")!)

        #expect(first.cacheKey == second.cacheKey)
        #expect(first.cacheKey != other.cacheKey)
        #expect(second.downloadURL.absoluteString.hasSuffix("sig=2"))
    }
}
