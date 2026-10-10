//
//  ChatTextFormatRenderingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Formatted text rendering")
struct ChatTextFormatRenderingTests {

    private func message(_ raw: String) -> ChatMessage {
        let formatted = ChatTextFormatter.format(detecting: raw)
        return ChatMessage(
            id: "1",
            text: formatted.display,
            sender: .me,
            linkPreview: formatted.preview,
            format: formatted.format
        )
    }

    private func font(_ text: NSAttributedString, at index: Int) -> UIFont? {
        text.attribute(.font, at: index, effectiveRange: nil) as? UIFont
    }

    @Test("The display text drops the markers and bold changes only the marked run")
    func boldRun() throws {
        let text = try #require(ChatBubbleView.displayText(for: message("a *b* c")))
        #expect(text.string == "a b c")
        #expect(font(text, at: 0) != font(text, at: 2))
        #expect(font(text, at: 0) == font(text, at: 4))
    }

    @Test("Strike and code draw their attributes over the span")
    func strikeAndCode() throws {
        let strike = try #require(ChatBubbleView.displayText(for: message("~gone~")))
        #expect(strike.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)

        let code = try #require(ChatBubbleView.displayText(for: message("`x`")))
        #expect(code.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
    }

    @Test("A quote marks its line for the bar and indents it")
    func quote() throws {
        let text = try #require(ChatBubbleView.displayText(for: message("> hello")))
        #expect(text.string == "hello")
        #expect(text.attribute(ChatTextStyling.quoteBar, at: 0, effectiveRange: nil) != nil)
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.firstLineHeadIndent == ChatTextStyling.quoteIndent)
    }

    @Test("A list item hangs its wrapped lines past the marker")
    func listHang() throws {
        let text = try #require(ChatBubbleView.displayText(for: message("- milk")))
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(text.string == "- milk")
        #expect(style?.headIndent == ChatTextStyling.bulletIndent)
        #expect(style?.firstLineHeadIndent == 0)
    }

    @Test("A message with a quote or list goes to the text view, plain styles stay on the label")
    func routing() {
        #expect(message("> hi").format?.needsTextView == true)
        #expect(message("- hi").format?.needsTextView == true)
        #expect(message("*hi*").format?.needsTextView == false)
    }

    @Test("A masked link is linked over its text in the text view's string")
    func maskedLinkAttribute() throws {
        let text = try #require(LinkableBubbleView.linkedText(for: message("[docs](https://example.com)")))
        #expect(text.string == "docs")
        #expect(text.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    }
}
