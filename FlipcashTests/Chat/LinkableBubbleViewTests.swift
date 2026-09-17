//
//  LinkableBubbleViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("LinkableBubbleView")
struct LinkableBubbleViewTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test("Configuring renders the message text")
    func configure_setsText() {
        let view = LinkableBubbleView()
        view.configure(with: ChatMessage(id: "1", text: "see https://apple.com", sender: .me))
        #expect(view.descendants(of: UITextView.self).first?.text == "see https://apple.com")
    }

    @Test("The text view refuses to become first responder, so selection stays off")
    func textView_refusesFirstResponder() {
        let view = LinkableBubbleView()
        #expect(view.descendants(of: UITextView.self).first?.canBecomeFirstResponder == false)
    }

    @Test("The text view's own data detection is off, so LinkDetector is the only detector")
    func textView_leavesDetectionToLinkDetector() {
        let view = LinkableBubbleView()
        #expect(view.descendants(of: UITextView.self).first?.dataDetectorTypes == [])
    }

    @Test("Every detected span gets a link attribute, not just the trailing one")
    func linkedText_marksEverySpan() throws {
        let text = "see https://apple.com and https://example.com"
        let message = ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            linkPreview: LinkPreview(links: [
                DetectedLink(range: NSRange(location: 4, length: 17), url: url("https://apple.com")),
                DetectedLink(range: NSRange(location: 26, length: 19), url: url("https://example.com")),
            ])
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message)).text
        var linked: [URL] = []
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if let url = value as? URL { linked.append(url) }
        }
        #expect(linked == [url("https://apple.com"), url("https://example.com")])
    }

    @Test("A span past the end of the text is dropped rather than trapping")
    func linkedText_clampsStaleSpans() throws {
        let message = ChatMessage(
            id: "1",
            text: "hi",
            sender: .me,
            linkPreview: LinkPreview(links: [
                DetectedLink(range: NSRange(location: 0, length: 40), url: url("https://apple.com")),
            ])
        )

        let rendered = try #require(LinkableBubbleView.linkedText(for: message)).text
        var linked = 0
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { linked += 1 }
        }
        #expect(linked == 0)
    }

    // MARK: - The carded link leaves the body

    /// The same four shapes Android's `LinkSpanRemovalTest` pins, so a message that gets a card
    /// reads the same on both platforms.
    private static let cashLink = "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"

    private func carded(_ text: String, at location: Int) -> ChatMessage {
        let link = DetectedLink(
            range: NSRange(location: location, length: (Self.cashLink as NSString).length),
            url: url(Self.cashLink)
        )
        return ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            linkPreview: LinkPreview(
                links: [link],
                card: .cash(
                    LinkCard.Cash(
                        url: link.url,
                        entropy: "KNi8pQr1n5hRU65vKJGge3",
                        range: link.range,
                        state: .unresolved
                    )
                )
            )
        )
    }

    @Test("A message that was nothing but the link leaves no body under the card")
    func linkedText_linkOnly() throws {
        let rendered = try #require(LinkableBubbleView.linkedText(for: carded(Self.cashLink, at: 0)))
        #expect(rendered.text.string.isEmpty)
        #expect(rendered.hasBody == false)
    }

    @Test("A link at the end takes the space in front of it")
    func linkedText_trailingLink() throws {
        let message = carded("here you go: \(Self.cashLink)", at: 13)
        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        #expect(rendered.text.string == "here you go:")
        #expect(rendered.hasBody)
    }

    @Test("A link mid-sentence takes one of its two spaces, not both and not neither")
    func linkedText_midSentenceLink() throws {
        let message = carded("check \(Self.cashLink) out", at: 6)
        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        #expect(rendered.text.string == "check out")
    }

    @Test("A link alone on its line takes the line with it")
    func linkedText_linkOnItsOwnLine() throws {
        let message = carded("here you go\n\(Self.cashLink)\nenjoy", at: 12)
        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        #expect(rendered.text.string == "here you go\nenjoy")
    }

    @Test("A card span past the end of the text leaves the body alone")
    func linkedText_staleCardSpanKeepsTheBody() throws {
        let message = carded("hi", at: 0)
        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        #expect(rendered.text.string == "hi")
        #expect(rendered.hasBody)
    }

    @Test("Tapping the card opens the link the card replaced")
    func cardTap_opensTheLink() {
        let view = LinkableBubbleView()
        var opened: [URL] = []
        view.onOpenURL = { opened.append($0) }
        view.configure(with: carded(Self.cashLink, at: 0))
        view.cardTapped()
        #expect(opened == [url(Self.cashLink)])
    }

    @Test("A bubble recycled from a carded message to a plain one opens nothing")
    func cardTap_afterReuse() {
        let view = LinkableBubbleView()
        var opened: [URL] = []
        view.onOpenURL = { opened.append($0) }
        view.configure(with: carded(Self.cashLink, at: 0))
        view.configure(with: ChatMessage(id: "2", text: "see https://apple.com", sender: .me))
        view.cardTapped()
        #expect(opened.isEmpty)
    }

    @Test("An inverted card span leaves the body alone")
    func cutRange_rejectsAnInvertedSpan() {
        let text = "here you go" as NSString
        #expect(LinkableBubbleView.cutRange(for: NSRange(location: 4, length: -2), in: text) == nil)
        #expect(LinkableBubbleView.cutRange(for: NSRange(location: -1, length: 4), in: text) == nil)
    }
}
