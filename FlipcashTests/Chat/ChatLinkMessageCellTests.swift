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

    private func chrome(_ cell: ChatLinkMessageCell) -> BubbleBackgroundView? {
        cell.descendants(of: BubbleBackgroundView.self).first
    }

    @Test("A message that was nothing but the link drops the bubble and runs the card its full width")
    func linkOnlyMessage_dropsTheBubble() {
        let maxWidth: CGFloat = 250
        let cell = makeCell()
        cell.configure(with: cardedMessage(text: Self.cashLink), maxWidth: maxWidth)
        #expect(layOut(cell).width == maxWidth)
        #expect(chrome(cell)?.isDrawingBubble == false)
    }

    @Test("Text alongside the card keeps the bubble, and keeps the card inside its padding")
    func cardedMessageWithText_keepsTheBubble() {
        let maxWidth: CGFloat = 250
        let cell = makeCell()
        cell.configure(with: cardedMessage(text: "\(Self.cashLink) enjoy"), maxWidth: maxWidth)
        #expect(layOut(cell).width < maxWidth)
        #expect(chrome(cell)?.isDrawingBubble == true)
    }

    @Test("A cell recycled from a bare card to a carded message puts the bubble back")
    func reusedCell_bareToCarded_restoresTheBubble() {
        let cell = makeCell()
        cell.configure(with: cardedMessage(text: Self.cashLink), maxWidth: 250)
        cell.layoutIfNeeded()
        cell.configure(with: cardedMessage(text: "\(Self.cashLink) enjoy"), maxWidth: 250)
        #expect(layOut(cell).width < 250)
        #expect(chrome(cell)?.isDrawingBubble == true)
    }

    /// What `ChatColumnCell.preferredLayoutAttributesFitting` asks the cell for, which is the height
    /// the transcript then lays the row out at.
    private func measure(_ cell: ChatLinkMessageCell, width: CGFloat) -> CGFloat {
        cell.contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    @Test("A cell recycled from a bare card measures the next row at its own geometry, not the bare one")
    func reusedCell_bareToCarded_measuresAtTheRestoredGeometry() {
        let carded = cardedMessage(text: "\(Self.cashLink) enjoy")
        let fresh = makeCell()
        fresh.configure(with: carded, maxWidth: 250)
        let expected = measure(fresh, width: 320)

        let recycled = makeCell()
        recycled.configure(with: cardedMessage(text: Self.cashLink), maxWidth: 250)
        _ = measure(recycled, width: 320)
        recycled.prepareForReuse()
        recycled.configure(with: carded, maxWidth: 250)

        #expect(measure(recycled, width: 320) == expected)
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
