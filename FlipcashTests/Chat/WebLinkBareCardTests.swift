import Foundation
import Testing
import UIKit
@testable import FlipcashCore
@testable import FlipcashUI

/// A message that is only its web link draws its preview bare, in place of its bubble, once the
/// preview draws; until then, and whenever there is no preview, it keeps its text bubble.
@MainActor
@Suite("Web link bare card")
struct WebLinkBareCardTests {

    /// Answers from `answers` at paint time and lets the test push later states by hand.
    private final class Source: LinkCardSource {
        var answers: [LinkCard: LinkCard.State] = [:]
        private var continuations: [LinkCard: AsyncStream<LinkCard.State>.Continuation] = [:]

        func known(_ card: LinkCard) -> LinkCard.State? { answers[card] }

        func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
            let (stream, continuation) = AsyncStream<LinkCard.State>.makeStream()
            continuations[card] = continuation
            return stream
        }

        func yield(_ state: LinkCard.State, for card: LinkCard) {
            continuations[card]?.yield(state)
        }
    }

    private static let link = "https://example.com/a"

    private static let page = LinkCard.Web.Resolved(
        title: "Example Title",
        description: nil,
        imageURL: nil,
        host: "example.com"
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
                card: .web(LinkCard.Web(url: url, range: range))
            )
        )
    }

    private static func card(of message: ChatMessage) -> LinkCard {
        message.linkPreview!.card!
    }

    private func bubble(_ source: Source, mode: WebLinkPreviewMode = .automatic) -> LinkableBubbleView {
        let bubble = LinkableBubbleView()
        bubble.linkCardSource = source
        bubble.webPreviewMode = mode
        return bubble
    }

    private func textView(_ bubble: LinkableBubbleView) -> UITextView? {
        bubble.descendants(of: UITextView.self).first
    }

    private func settle(until condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
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

    @Test("A remembered preview draws bare from the first frame")
    func rememberedPreview_isBareAtOnce() {
        let source = Source()
        let message = Self.message()
        source.answers[Self.card(of: message)] = .web(.resolved(Self.page))
        let bubble = bubble(source)
        bubble.configure(with: message)

        #expect(bubble.isBare)
        #expect(textView(bubble)?.isHidden == true)
    }

    @Test("While loading a link-only row draws its placeholder bare, then fills it in place")
    func loadingThenResolved_fillsThePlaceholder() async {
        let source = Source()
        let message = Self.message()
        let bubble = bubble(source)
        var changes = 0
        bubble.onBareChange = { changes += 1 }
        bubble.configure(with: message)

        #expect(bubble.isBare)
        #expect(textView(bubble)?.isHidden == true)

        source.yield(.web(.resolved(Self.page)), for: Self.card(of: message))
        #expect(await settle { if case .preview = bubble.cardView.webView.content { true } else { false } })
        #expect(bubble.isBare)
        #expect(changes == 0)
    }

    @Test("A placeholder whose page has nothing puts the text bubble back")
    func loadingThenNone_restoresTheBubble() async {
        let source = Source()
        let message = Self.message()
        let bubble = bubble(source)
        bubble.configure(with: message)
        #expect(bubble.isBare)

        source.yield(.web(.none), for: Self.card(of: message))
        #expect(await settle { !bubble.isBare })
        #expect(textView(bubble)?.attributedText.string == Self.link)
    }

    @Test("A remembered nothing draws the text bubble from the first frame, no placeholder")
    func rememberedNone_skipsThePlaceholder() {
        let source = Source()
        let message = Self.message()
        source.answers[Self.card(of: message)] = .web(.none)
        let bubble = bubble(source)
        bubble.configure(with: message)

        #expect(!bubble.isBare)
        #expect(bubble.cardView.webView.content == .nothing)
    }

    @Test("A preview that goes away puts the text bubble back, never an empty row")
    func previewGone_restoresTheBubble() async {
        let source = Source()
        let message = Self.message()
        source.answers[Self.card(of: message)] = .web(.resolved(Self.page))
        let bubble = bubble(source)
        bubble.configure(with: message)
        #expect(bubble.isBare)

        source.yield(.web(.none), for: Self.card(of: message))
        #expect(await settle { !bubble.isBare })
        #expect(textView(bubble)?.isHidden == false)
        #expect(textView(bubble)?.attributedText.string == Self.link)
    }

    @Test("Text beside the link keeps the card inside the bubble")
    func textAndLink_staysInTheBubble() {
        let source = Source()
        let message = Self.message(prefix: "look ")
        source.answers[Self.card(of: message)] = .web(.resolved(Self.page))
        let bubble = bubble(source)
        bubble.configure(with: message)

        #expect(!bubble.isBare)
        #expect(textView(bubble)?.isHidden == false)
    }

    @Test("Text beside a loading link draws nothing under it")
    func textAndLoadingLink_drawsNoPlaceholder() {
        let source = Source()
        let message = Self.message(prefix: "look ")
        let bubble = bubble(source)
        bubble.configure(with: message)

        #expect(!bubble.isBare)
        #expect(bubble.cardView.webView.content == .nothing)
    }

    @Test("A link-only row at its chip keeps its bubble")
    func chip_keepsTheBubble() {
        let source = Source()
        let message = Self.message()
        let bubble = bubble(source, mode: .tapToLoad)
        bubble.configure(with: message)

        #expect(!bubble.isBare)
    }

    @Test("Tapping a link-only row's chip draws the placeholder while it loads")
    func chipTapped_drawsThePlaceholder() {
        let source = Source()
        let message = Self.message()
        let bubble = bubble(source, mode: .tapToLoad)
        bubble.configure(with: message)
        #expect(!bubble.isBare)

        bubble.cardView.webView.chip.sendActions(for: .touchUpInside)

        #expect(bubble.isBare)
        #expect(bubble.cardView.webView.content == .placeholder(host: "example.com", url: URL(string: Self.link)!))
    }

    @Test("The placeholder shows the link's host without www, holds the image slot, and reads as the link")
    func placeholder_content() throws {
        let url = try #require(URL(string: "https://www.example.com/a"))
        let view = LinkWebCardView(frame: CGRect(x: 0, y: 0, width: 250, height: 300))
        view.configure(with: .placeholder(host: "example.com", url: url))

        #expect(view.hostLabel.text == "example.com")
        #expect(view.imageSlot == .loading)
        #expect(view.titleLabel.isHidden)
        #expect(view.descriptionLabel.isHidden)
        let panel = try #require(view.hostLabel.superview?.superview)
        #expect(panel.isAccessibilityElement)
        #expect(panel.accessibilityLabel == url.absoluteString)

        view.configure(with: .preview(Self.page))
        #expect(!panel.isAccessibilityElement)
        #expect(!view.titleLabel.isHidden)
        #expect(view.imageSlot == .none)
    }

    // MARK: - Buttons keep their single tap

    private func laidOut(_ card: LinkCard, source: Source, mode: WebLinkPreviewMode = .automatic) -> LinkCardView {
        let view = LinkCardView(frame: CGRect(x: 0, y: 0, width: 250, height: 300))
        view.webPreviewMode = mode
        view.configure(with: card, source: source)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return view
    }

    @Test("The web chip is a button; the rest of the card is not")
    func webChip_isAButton() throws {
        let message = Self.message()
        let view = laidOut(Self.card(of: message), source: Source(), mode: .tapToLoad)
        let chip = try #require(view.descendants(of: LinkWebCardView.self).first?.chip)
        #expect(!chip.isHidden)

        let center = view.convert(CGPoint(x: chip.bounds.midX, y: chip.bounds.midY), from: chip)
        #expect(view.hasButton(at: center))
        #expect(!view.hasButton(at: CGPoint(x: view.bounds.maxX - 1, y: view.bounds.maxY - 1)))
    }

    @Test("The cash card's claim pill is a button; its body is not")
    func cashPill_isAButton() {
        let link = "https://send.flipcash.com/c/#/e=abc"
        let card = LinkCard.cash(LinkCard.Cash(
            url: URL(string: link)!,
            entropy: "abc",
            range: NSRange(location: 0, length: (link as NSString).length)
        ))
        let view = laidOut(card, source: Source())

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
        let source = Source()
        let message = Self.message()
        source.answers[Self.card(of: message)] = .web(.resolved(Self.page))
        let cell = ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
        cell.linkCardSource = source
        cell.webPreviewMode = .automatic
        cell.configure(with: message, maxWidth: 250)
        cell.contentView.setNeedsLayout()
        cell.contentView.layoutIfNeeded()

        let bubble = cell.descendants(of: LinkableBubbleView.self).first
        #expect(bubble?.isBare == true)
        #expect(bubble?.bounds.width == 250)
    }
}
