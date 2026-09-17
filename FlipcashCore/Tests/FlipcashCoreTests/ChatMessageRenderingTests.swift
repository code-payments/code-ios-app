//
//  ChatMessageRenderingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ChatMessage bare-emoji rendering")
struct ChatMessageRenderingTests {

    private func message(
        text: String = "👍",
        isEmojiOnly: Bool = true,
        linkPreview: LinkPreview? = nil,
        quote: ChatQuote? = nil
    ) -> ChatMessage {
        ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            isEmojiOnly: isEmojiOnly,
            linkPreview: linkPreview,
            quote: quote
        )
    }

    @Test("An emoji-only text row renders bare")
    func emojiOnlyTextRendersBare() {
        #expect(message().rendersAsLargeEmoji)
    }

    @Test("A row the mapper did not flag renders as a bubble")
    func unflaggedRowKeepsBubble() {
        #expect(!message(text: "hello", isEmojiOnly: false).rendersAsLargeEmoji)
    }

    @Test("A reply keeps its bubble — the quote panel lives inside it")
    func replyKeepsBubble() {
        let quote = ChatQuote(stableID: "0", authorName: "Them", snippet: "hi", kind: .text)
        #expect(!message(quote: quote).rendersAsLargeEmoji)
    }

    @Test("A link row keeps its bubble")
    func linkRowKeepsBubble() {
        let preview = LinkPreview(url: URL(string: "https://example.com")!)
        #expect(!message(linkPreview: preview).rendersAsLargeEmoji)
    }

    @Test("Cash and tombstone rows never render bare")
    func nonTextContentKeepsItsChrome() {
        let cash = ChatMessage(
            id: "1",
            content: .cash(ChatCashContent(amount: "$1.00", token: "Cash")),
            sender: .me,
            isEmojiOnly: true
        )
        let deleted = ChatMessage(
            id: "2",
            content: .deleted("This message was deleted"),
            sender: .me,
            isEmojiOnly: true
        )
        #expect(!cash.rendersAsLargeEmoji)
        #expect(!deleted.rendersAsLargeEmoji)
    }

    @Test("The bubble run defaults off and is independent of the author run")
    func bubbleRunIsItsOwnPair() {
        let row = ChatMessage(
            id: "1",
            text: "hi",
            sender: .me,
            isContinuationFromPrevious: true,
            isContinuedByNext: true
        )
        #expect(!row.joinsBubbleAbove)
        #expect(!row.joinsBubbleBelow)
    }

    @Test("The notification preview flags an emoji-only row the way the transcript does")
    func previewFlagsEmojiOnly() {
        let sender = UUID()
        let messages = [
            ConversationMessage(
                id: MessageID(value: 1), senderID: sender, content: .text("👍"),
                date: Date(timeIntervalSince1970: 1_000_000), unreadSeq: 1
            ),
        ]
        let items = ChatItem.preview(from: messages, selfUserID: sender)
        let rows: [ChatMessage] = items.compactMap { item in
            switch item {
            case .message(let message): return message
            default:                    return nil
            }
        }
        #expect(rows.count == 1)
        #expect(rows[0].rendersAsLargeEmoji)
    }
}
