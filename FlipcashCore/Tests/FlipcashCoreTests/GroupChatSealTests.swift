//
//  GroupChatSealTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
import SharedCore
@testable import FlipcashCore

@Suite("ChatSeal in a private group")
struct GroupChatSealTests {

    private let groupKey = Data(repeating: 0x42, count: 32)
    private let hostID = UUID()
    private let memberID = UUID()
    private let chatID = ConversationID(data: Data(repeating: 9, count: 32))
    private let blobID = BlobID(data: Data(repeating: 0xA5, count: 16))

    private func seal(selfID: UUID, key: Data? = nil, chat: ConversationID? = nil) -> ChatSeal {
        ChatSeal(cipher: DefaultChatCipher.shared, groupKey: key ?? groupKey, conversationID: chat ?? chatID, selfUserID: selfID)
    }

    private func message(_ content: Flipcash_Messaging_V1_Content, from sender: UUID) throws -> ConversationMessage {
        let proto = Flipcash_Messaging_V1_Message.with {
            $0.messageID = MessageID(value: 7).proto
            $0.senderID = sender.proto
            $0.content = [content]
        }
        return try #require(ConversationMessage(proto))
    }

    @Test("Sealed content uses the chat-key scheme")
    func wireScheme() throws {
        let sealed = try seal(selfID: hostID).seal(text: "hi", repliedTo: nil)

        #expect(sealed.encrypted.scheme == .chatKeyXchacha20Poly1305)
        #expect(sealed.encrypted.nonce.count == 24)
    }

    @Test("Another member opens what the host sealed, and so does the host")
    func roundTrip() throws {
        let sealed = try seal(selfID: hostID).seal(text: "welcome", repliedTo: nil)

        #expect(seal(selfID: memberID).open(try message(sealed, from: hostID)).content == .text("welcome"))
        #expect(seal(selfID: hostID).open(try message(sealed, from: hostID)).content == .text("welcome"))
    }

    @Test("A message claimed by a different sender fails authentication")
    func wrongSender() throws {
        let sealed = try seal(selfID: hostID).seal(text: "welcome", repliedTo: nil)
        let opened = seal(selfID: memberID).open(try message(sealed, from: memberID))

        #expect(opened.decryptFailure == .authentication)
    }

    @Test("A different group key fails authentication")
    func wrongKey() throws {
        let sealed = try seal(selfID: hostID).seal(text: "welcome", repliedTo: nil)
        let opened = seal(selfID: memberID, key: Data(repeating: 1, count: 32)).open(try message(sealed, from: hostID))

        #expect(opened.decryptFailure == .authentication)
    }

    @Test("A DM-scheme message in a group seal is unsupported")
    func dmSchemeUnsupported() throws {
        var sealed = try seal(selfID: hostID).seal(text: "x", repliedTo: nil)
        sealed.encrypted.scheme = .x25519Xchacha20Poly1305
        let opened = seal(selfID: memberID).open(try message(sealed, from: hostID))

        #expect(opened.decryptFailure == .unsupported)
    }

    @Test("A photo blob round-trips for the uploader and another member")
    func blobRoundTrip() throws {
        let image = Data((0..<500).map { UInt8($0 % 251) })
        let blob = try seal(selfID: hostID).encryptBlob(image, blobID: blobID)
        let sealed = SealedBlob(senderID: hostID, plaintextSize: image.count)

        #expect(try seal(selfID: memberID).decryptBlob(blob, blobID: blobID, sealed: sealed) == image)
        #expect(try seal(selfID: hostID).decryptBlob(blob, blobID: blobID, sealed: sealed) == image)
    }

    @Test("A blob opened under another chat fails")
    func blobWrongChat() throws {
        let image = Data(repeating: 3, count: 100)
        let blob = try seal(selfID: hostID).encryptBlob(image, blobID: blobID)
        let other = ConversationID(data: Data(repeating: 1, count: 32))

        #expect(throws: (any Error).self) {
            try seal(selfID: memberID, chat: other).decryptBlob(blob, blobID: blobID, sealed: SealedBlob(senderID: hostID, plaintextSize: 100))
        }
    }
}
