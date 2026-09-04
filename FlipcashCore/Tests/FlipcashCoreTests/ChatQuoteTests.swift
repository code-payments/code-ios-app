//
//  ChatQuoteTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
@testable import FlipcashCore

@Suite("ChatQuote")
struct ChatQuoteTests {

    @Test("A short snippet is left alone")
    func shortSnippet_isUnchanged() {
        #expect(ChatQuote.snippet(forText: "on my way") == "on my way")
    }

    @Test("A long snippet is truncated with an ellipsis at the limit")
    func longSnippet_isTruncated() {
        let text = String(repeating: "a", count: ChatQuote.snippetLimit + 40)
        let snippet = ChatQuote.snippet(forText: text)
        #expect(snippet.count == ChatQuote.snippetLimit + 1)
        #expect(snippet.hasSuffix("…"))
    }

    @Test("Newlines collapse so the snippet stays one line")
    func newlines_collapse() {
        #expect(ChatQuote.snippet(forText: "line one\nline two") == "line one line two")
    }

    @Test("A quote with no target cannot be jumped to")
    func unresolvedQuote_hasNoTarget() {
        let quote = ChatQuote(stableID: nil, authorName: "", snippet: ChatQuote.unavailableSnippet, kind: .unavailable)
        #expect(quote.isJumpable == false)
    }

    @Test("A resolved quote can be jumped to")
    func resolvedQuote_hasTarget() {
        let quote = ChatQuote(stableID: "7", authorName: "You", snippet: "hi", kind: .text)
        #expect(quote.isJumpable)
    }

    @Test("A message carries no quote by default")
    func chatMessage_defaultsToNoQuote() {
        #expect(ChatMessage(id: "1", text: "hi", sender: .me).quote == nil)
    }
}
