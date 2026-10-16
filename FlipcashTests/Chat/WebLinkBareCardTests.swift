import Foundation
import Testing
import UIKit
@testable import FlipcashCore
@testable import FlipcashUI

/// A message that is only its web link draws the sender's preview bare, in place of its bubble,
/// from the first frame; text beside the link keeps the card inside the bubble.
@MainActor
@Suite("Web link bare card")
struct WebLinkBareCardTests {

    private static let link = "https://example.com/a"

    private static let page = MessageLinkPreview(
        url: link,
        title: "Example Title",
        description: nil,
        image: nil
    )

    /// A text message whose web card is the link at `prefix.count` in `prefix + link + suffix`.
    private static func message(prefix: String = "", suffix: String = "") -> ChatMessage {
        let text = prefix + link + suffix
        let range = NSRange(location: (prefix as NSString).length, length: (link as NSString).length)
        let url = URL(string: link)!
        return ChatMessage(
            id: "1",
            text: text,
            sender: .other,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: range, url: url)],
                card: .web(LinkCard.Web(url: url, range: range, page: page))
            )
        )
    }

    private func textView(_ bubble: LinkableBubbleView) -> UITextView? {
        bubble.descendants(of: UITextView.self).first
    }

    // MARK: - Model

    @Test("Only the link, give or take whitespace and punctuation around it")
    func onlyItsWebLink() {
        #expect(Self.message().isOnlyItsWebLink)
        #expect(Self.message(prefix: "  (", suffix: ").\n").isOnlyItsWebLink)
        #expect(!Self.message(prefix: "look ").isOnlyItsWebLink)
        #expect(!Self.message(suffix: " hi").isOnlyItsWebLink)
    }

    @Test("A Flipcash card row is never a link-only web row")
    func flipcashCardIsNotWeb() {
        let link = "https://send.flipcash.com/c/#/e=abc"
        let range = NSRange(location: 0, length: (link as NSString).length)
        let message = ChatMessage(
            id: "1",
            text: link,
            sender: .other,
            linkPreview: LinkPreview(
                links: [DetectedLink(range: range, url: URL(string: link)!)],
                card: .cash(LinkCard.Cash(url: URL(string: link)!, entropy: "abc", range: range))
            )
        )
        #expect(!message.isOnlyItsWebLink)
        // A card, bare or not, takes the double tap; its own buttons keep their first tap.
        #expect(message.takesDoubleTapReaction)
    }

    // MARK: - Bubble

    @Test("A sent preview draws bare from the first frame")
    func sentPreview_isBareAtOnce() {
        let bubble = LinkableBubbleView()
        bubble.configure(with: Self.message())

        #expect(bubble.isBare)
        #expect(textView(bubble)?.isHidden == true)
    }

    @Test("Text beside the link keeps the card inside the bubble")
    func textAndLink_staysInTheBubble() {
        let bubble = LinkableBubbleView()
        bubble.configure(with: Self.message(prefix: "look "))

        #expect(!bubble.isBare)
        #expect(textView(bubble)?.isHidden == false)
    }

    // MARK: - Buttons keep their single tap

    @Test("The cash card's claim pill is a button; its body is not")
    func cashPill_isAButton() {
        let link = "https://send.flipcash.com/c/#/e=abc"
        let card = LinkCard.cash(LinkCard.Cash(
            url: URL(string: link)!,
            entropy: "abc",
            range: NSRange(location: 0, length: (link as NSString).length)
        ))
        let view = LinkCardView(frame: CGRect(x: 0, y: 0, width: 250, height: 300))
        view.configure(with: card, source: nil)
        view.setNeedsLayout()
        view.layoutIfNeeded()

        let points = stride(from: 0.0, to: view.bounds.width, by: 4).flatMap { x in
            stride(from: 0.0, to: view.bounds.height, by: 4).map { CGPoint(x: x, y: $0) }
        }
        let onButton = points.filter(view.hasButton(at:))
        #expect(!onButton.isEmpty)
        #expect(onButton.count < points.count / 2)
    }

    // MARK: - Cell

    @Test("A bare web card runs to the bubble's full width")
    func bareCell_fillsTheWidth() {
        let cell = ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        cell.configure(with: Self.message(), maxWidth: 250)
        cell.contentView.setNeedsLayout()
        cell.contentView.layoutIfNeeded()

        let bubble = cell.descendants(of: LinkableBubbleView.self).first
        #expect(bubble?.isBare == true)
        #expect(bubble?.bounds.width == 250)
    }

    /// L6: an opaque page image can match the chat background, so a bare card draws an outline over
    /// it; inside a bubble the bubble is the edge.
    @Test func aBareWebCardDrawsAnOutlineOverItsImage() {
        let view = LinkWebCardView(frame: CGRect(x: 0, y: 0, width: 250, height: 300))
        view.isBare = true
        view.layoutIfNeeded()
        #expect(view.outline.superlayer != nil)
        #expect(view.outline.superlayer?.sublayers?.last === view.outline)

        view.isBare = false
        view.layoutIfNeeded()
        #expect(view.outline.superlayer == nil)
    }
}
