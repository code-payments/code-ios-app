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

    /// A recycled cell carries the previous row's layout into the next measurement: a non-scrolling
    /// `UITextView` derives its intrinsic height from the width it was last laid out at, not from
    /// the width being asked about. Measured straight after a narrow row, it reports the wrap it had
    /// there, and the transcript lays the row out that much too tall.
    @Test("A cell measured once at a narrow width measures the next row at the width being asked about")
    func narrowThenWide_measuresAtTheWidthAsked() {
        let carded = cardedMessage(text: "\(Self.cashLink) Check out Jeffy")
        let fresh = makeCell()
        fresh.configure(with: carded, maxWidth: 313)
        let expected = measure(fresh, width: 402)

        let recycled = makeCell()
        recycled.configure(with: carded, maxWidth: 90)
        _ = measure(recycled, width: 120)
        recycled.prepareForReuse()
        recycled.configure(with: carded, maxWidth: 313)

        #expect(measure(recycled, width: 402) == expected)
    }

    /// The transcript lays a row out at an estimated height before it has measured it. The card's
    /// proportions and its pins to the bubble's sides are all required, so a row held shorter than
    /// its content has only one place to give: the bubble's width. It collapses, the text view's
    /// container keeps that width, and the next measurement wraps a single line into three.
    @Test("A row laid out shorter than its content does not narrow the bubble into the next measurement")
    func undersizedRow_doesNotNarrowTheBubble() {
        let cell = ChatLinkMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 56))
        cell.configure(with: cardedMessage(text: "\(Self.cashLink) Check out Jeffy"), maxWidth: 313.56)
        let natural = measure(cell, width: 402)

        cell.frame = CGRect(x: 0, y: 0, width: 402, height: 56)
        cell.layoutIfNeeded()

        #expect(measure(cell, width: 402) == natural)
    }

    /// The transcript can hold a row at a height its content no longer wants — a receipt that
    /// cleared, a card that shrank — until the layout re-measures. The bubble is the lowest-hugging
    /// view in the column, so a column stretched to fill the row used to hand it all of that
    /// surplus and draw its chrome tall around unchanged text.
    @Test("A row held taller than its content leaves the bubble at its own height")
    func oversizedRow_doesNotStretchTheBubble() {
        let cell = makeCell()
        cell.configure(with: cardedMessage(text: "\(Self.cashLink) enjoy"), maxWidth: 250)
        let natural = measure(cell, width: 320)

        cell.frame = CGRect(x: 0, y: 0, width: 320, height: natural + 40)
        cell.layoutIfNeeded()

        let bubble = cell.descendants(of: LinkableBubbleView.self).first
        #expect((bubble?.bounds.height ?? 0) <= natural, "bubble was \(bubble?.bounds ?? .zero)")
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
