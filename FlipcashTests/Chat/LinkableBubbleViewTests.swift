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

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
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

        let rendered = try #require(LinkableBubbleView.linkedText(for: message))
        var linked = 0
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            if value != nil { linked += 1 }
        }
        #expect(linked == 0)
    }
}
