//
//  ChatPreviewDecryptionTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("Notification preview of encrypted messages")
struct ChatPreviewDecryptionTests {

    private let me = UUID()
    private let them = UUID()
    private let sealed = ConversationMessage.Sealed(scheme: 1, nonce: Data([1]), ciphertext: Data([2]))

    private func encrypted(_ id: UInt64, from sender: UUID, text: String? = nil, failure: ConversationMessage.DecryptFailure? = nil) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id),
            senderID: sender,
            content: text.map { .text($0) } ?? .encrypted(scheme: sealed.scheme, nonce: sealed.nonce, ciphertext: sealed.ciphertext),
            date: Date(timeIntervalSince1970: 1_000_000 + TimeInterval(id)),
            unreadSeq: id,
            sealed: sealed,
            decryptFailure: failure
        )
    }

    private func contents(_ items: [ChatItem]) -> [ChatMessage.Content] {
        items.compactMap { if case .message(let message) = $0 { message.content } else { nil } }
    }

    @Test("A decrypted message previews as its plaintext")
    func decryptedPreviewsPlaintext() {
        let items = ChatItem.preview(from: [encrypted(1, from: them, text: "hello")], selfUserID: me)
        #expect(contents(items) == [.text("hello")])
    }

    @Test("A message waiting on the peer's key is left out of the preview")
    func awaitingIsLeftOut() {
        let items = ChatItem.preview(from: [encrypted(1, from: them, text: "hi"), encrypted(2, from: them)], selfUserID: me)
        #expect(contents(items) == [.text("hi")])
    }

    @Test("A failed message previews with the hint its cause calls for")
    func failureHints() {
        func hint(_ sender: UUID, _ failure: ConversationMessage.DecryptFailure) -> [ChatMessage.Content] {
            contents(ChatItem.preview(from: [encrypted(1, from: sender, failure: failure)], selfUserID: me, counterpartName: "Ada Lovelace"))
        }
        #expect(hint(them, .unsupported) == [.unavailable(.updateApp)])
        #expect(hint(them, .authentication) == [.unavailable(.askToResend(firstName: "Ada"))])
        #expect(hint(me, .authentication) == [.unavailable(.resend)])
    }

    @Test("The hint's copy")
    func hintCopy() {
        #expect(ChatMessage.UnavailableHint.updateApp.text == "Update Flipcash to see it")
        #expect(ChatMessage.UnavailableHint.askToResend(firstName: "Ada").text == "Ask Ada to send it again")
        #expect(ChatMessage.UnavailableHint.resend.text == "Try sending it again")
    }
}
