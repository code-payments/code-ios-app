//
//  MessageLinkPreviewTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
import SharedCore
@testable import FlipcashCore

/// SharedCore exports its own `KeyPair`; these tests mean the app's.
private typealias KeyPair = FlipcashCore.KeyPair

@Suite("MessageLinkPreview")
struct MessageLinkPreviewTests {

    private let alice = KeyPair.generate()!
    private let bob = KeyPair.generate()!
    private let aliceID = UUID()
    private let bobID = UUID()
    private let chatID = ConversationID(data: Data(repeating: 7, count: 32))
    private let blobID = BlobID(data: Data(repeating: 0xA5, count: 16))

    private let text = "look https://example.com/a"

    private func seal(owner: KeyPair, peer: KeyPair, selfID: UUID) throws -> ChatSeal {
        try ChatSeal(cipher: DefaultChatCipher.shared, owner: owner, peerPublicKey: peer.publicKey, conversationID: chatID, selfUserID: selfID)
    }

    private func message(_ content: Flipcash_Messaging_V1_Content, from sender: UUID) throws -> ConversationMessage {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = MessageID(value: 42).proto
            $0.senderID = sender.proto
            $0.content = [content]
        }
        return try #require(ConversationMessage(proto))
    }

    private func preview(url: String = "https://example.com/a", title: String = "Example", image: MediaAttachment? = nil) -> MessageLinkPreview {
        MessageLinkPreview(url: url, title: title, description: "A page", image: image)
    }

    @Test("A plaintext preview comes back from the wire as sent")
    func plaintextRoundTrip() throws {
        let image = MediaAttachment(blobID: blobID, width: 0, height: 0, blurhash: nil)
        let sent = preview(image: image)
        let received = try message(.plaintext(text: text, repliedTo: nil, linkPreview: sent), from: aliceID)

        #expect(received.content == .text(text))
        #expect(received.linkPreview == sent)
    }

    @Test("A reply carries its preview")
    func replyRoundTrip() throws {
        let received = try message(.plaintext(text: text, repliedTo: MessageID(value: 9), linkPreview: preview()), from: aliceID)

        #expect(received.repliedTo == MessageID(value: 9))
        #expect(received.linkPreview == preview())
    }

    @Test("A sealed preview decrypts with its sealed image")
    func sealedRoundTrip() throws {
        let image = MediaAttachment(
            blobID: blobID, width: 640, height: 480, blurhash: "LEHV6nWB2yk8",
            sealed: SealedBlob(senderID: aliceID, plaintextSize: 1234)
        )
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: text, repliedTo: nil, linkPreview: preview(image: image))
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.content == .text(text))
        #expect(opened.linkPreview == preview(image: image))
    }

    @Test("A sealed message leaves off an image uploaded in plaintext")
    func sealedDropsPlainImage() throws {
        let plainImage = MediaAttachment(blobID: blobID, width: 0, height: 0, blurhash: nil)
        let sealed = try seal(owner: alice, peer: bob, selfID: aliceID).seal(text: text, repliedTo: nil, linkPreview: preview(image: plainImage))
        let opened = try seal(owner: bob, peer: alice, selfID: bobID).open(message(sealed, from: aliceID))

        #expect(opened.linkPreview == preview())
    }

    @Test("A preview whose url is not a whole link in the text is dropped on read")
    func notWholeLink() throws {
        let received = try message(.plaintext(text: text, repliedTo: nil, linkPreview: preview(url: "https://example.com")), from: aliceID)

        #expect(received.content == .text(text))
        #expect(received.linkPreview == nil)
    }

    @Test("A preview with an empty title is dropped on read")
    func emptyTitle() throws {
        let received = try message(.plaintext(text: text, repliedTo: nil, linkPreview: preview(title: "  ")), from: aliceID)

        #expect(received.linkPreview == nil)
    }

    @Test("An edit keeps the preview only while its link is still whole in the text")
    func keptForEdit() {
        #expect(preview().kept(for: "now https://example.com/a!") == preview())
        #expect(preview().kept(for: "gone") == nil)
    }
}
