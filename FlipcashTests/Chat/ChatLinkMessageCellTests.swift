import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatLinkMessageCell")
struct ChatLinkMessageCellTests {

    private func url(_ s: String) -> URL { URL(string: s)! }

    private func makeCell() -> ChatLinkMessageCell {
        ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
    }

    @Test("A failed link message disables the bubble's own link taps so retry wins")
    func failedMessage_disablesBubbleInteraction() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              receipt: .failed("Not Delivered. Tap to retry"),
                              linkPreview: LinkPreview(url: url("https://apple.com"))),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == false)
    }

    @Test("A non-failed link message keeps the bubble's link taps enabled")
    func nonFailedMessage_keepsBubbleInteractionEnabled() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "https://apple.com", sender: .me,
                              linkPreview: LinkPreview(url: url("https://apple.com"))),
            maxWidth: 250
        )
        #expect(cell.descendants(of: LinkableBubbleView.self).first?.isUserInteractionEnabled == true)
    }

    private static let cashLink = "https://send.flipcash.com/c/#/e=KNi8pQr1n5hRU65vKJGge3"

    private func cardedMessage(text: String) -> ChatMessage {
        let link = DetectedLink(
            range: NSRange(location: 0, length: (Self.cashLink as NSString).length),
            url: url(Self.cashLink)
        )
        return ChatMessage(
            id: "1",
            text: text,
            sender: .me,
            linkPreview: LinkPreview(
                links: [link],
                card: .cash(
                    LinkCard.Cash(url: link.url, entropy: "KNi8pQr1n5hRU65vKJGge3",
                                  range: link.range, state: .unresolved)
                )
            )
        )
    }

    private func layOut(_ cell: ChatLinkMessageCell) -> CGRect {
        cell.layoutIfNeeded()
        return cell.descendants(of: LinkCashCardView.self).first?.frame ?? .zero
    }

    @Test("A message that was nothing but the link still sizes its card, with no text to widen it")
    func linkOnlyMessage_holdsTheBubbleOpen() {
        let maxWidth: CGFloat = 250
        let cell = makeCell()
        cell.configure(with: cardedMessage(text: Self.cashLink), maxWidth: maxWidth)
        let card = layOut(cell)
        #expect(card.width > maxWidth / 2, "card was \(card)")
        #expect(card.height > 0)
    }

    @Test("A card message with text alongside it gets the same card as one without")
    func cardedMessage_sizesTheCardTheSameWithOrWithoutText() {
        let bare = makeCell()
        bare.configure(with: cardedMessage(text: Self.cashLink), maxWidth: 250)
        let withText = makeCell()
        withText.configure(with: cardedMessage(text: "\(Self.cashLink) enjoy"), maxWidth: 250)
        #expect(layOut(bare).size == layOut(withText).size)
    }

    @Test("A message with no card leaves the bubble sized by its text")
    func uncardedMessage_leavesTheBubbleToItsText() {
        let cell = makeCell()
        cell.configure(
            with: ChatMessage(id: "1", text: "hi", sender: .me,
                              linkPreview: LinkPreview(url: url("https://apple.com"))),
            maxWidth: 250
        )
        cell.layoutIfNeeded()
        let bubble = cell.descendants(of: LinkableBubbleView.self).first
        #expect((bubble?.bounds.width ?? 0) < 250)
    }
}
