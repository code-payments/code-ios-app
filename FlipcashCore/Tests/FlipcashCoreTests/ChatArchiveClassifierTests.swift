//
//  ChatArchiveClassifierTests.swift
//  FlipcashCoreTests
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Chat archive classifier")
struct ChatArchiveClassifierTests {

    private func message(_ text: String, id: UInt64 = 10, repliedTo: UInt64? = nil) -> ConversationMessage {
        ConversationMessage(
            id: MessageID(value: id), senderID: UUID(), content: .text(text),
            date: .now, unreadSeq: 0, repliedTo: repliedTo.map { MessageID(value: $0) }
        )
    }

    // MARK: mentions

    @Test("A text that @mentions the viewer's handle is a mention")
    func mention() {
        #expect(ChatArchiveClassifier.mentionsViewer(message("hey @Ana look"), viewerUsername: "ana") == .yes)
    }

    @Test("A text that mentions someone else is not")
    func otherMention() {
        #expect(ChatArchiveClassifier.mentionsViewer(message("hey @bob"), viewerUsername: "ana") == .no)
    }

    @Test("A mention inside a link is not a mention")
    func mentionInLink() {
        #expect(ChatArchiveClassifier.mentionsViewer(message("https://x.com/@ana"), viewerUsername: "ana") == .no)
    }

    @Test("Without the viewer's handle the answer is unknown")
    func noHandle() {
        #expect(ChatArchiveClassifier.mentionsViewer(message("hey @ana"), viewerUsername: nil) == .unknown)
    }

    @Test("Content that is still encrypted is unknown")
    func encrypted() {
        let m = ConversationMessage(
            id: MessageID(value: 1), senderID: UUID(),
            content: .encrypted(scheme: 1, nonce: Data(), ciphertext: Data()), date: .now, unreadSeq: 0
        )
        #expect(ChatArchiveClassifier.mentionsViewer(m, viewerUsername: "ana") == .unknown)
    }

    // MARK: replies

    @Test("A reply to the viewer's own message is a reply to the viewer")
    func replyToViewer() {
        let me = UUID()
        let result = ChatArchiveClassifier.repliesToViewer(
            message("ok", repliedTo: 3), selfUserID: me, authorOf: { _ in me }
        )
        #expect(result == .yes)
    }

    @Test("A reply to someone else's message is not")
    func replyToOther() {
        let result = ChatArchiveClassifier.repliesToViewer(
            message("ok", repliedTo: 3), selfUserID: UUID(), authorOf: { _ in UUID() }
        )
        #expect(result == .no)
    }

    @Test("A reply whose target is not stored is unknown")
    func replyUnknownTarget() {
        let result = ChatArchiveClassifier.repliesToViewer(
            message("ok", repliedTo: 3), selfUserID: UUID(), authorOf: { _ in nil }
        )
        #expect(result == .unknown)
    }

    @Test("A message that replies to nothing is not a reply")
    func notAReply() {
        let result = ChatArchiveClassifier.repliesToViewer(
            message("hi"), selfUserID: UUID(), authorOf: { _ in nil }
        )
        #expect(result == .no)
    }
}
