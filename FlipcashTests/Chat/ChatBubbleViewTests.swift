//
//  ChatBubbleViewTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import SwiftUI
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("Bubble corner grouping")
struct ChatBubbleViewCornerTests {

    private let base = BubbleBackgroundView.baseRadius      // 12
    private let grouped = BubbleBackgroundView.groupedRadius // 4

    @Test("A standalone bubble uses the base radius on all four corners")
    func standalone_allBase() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: false)
        #expect(r == RectangleCornerRadii(topLeading: base, bottomLeading: base, bottomTrailing: base, topTrailing: base))
    }

    @Test("A self bubble continued below flattens only its inner (trailing) bottom corner")
    func selfContinuedBelow_flattensInnerBottom() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: true)
        #expect(r.bottomTrailing == grouped) // inner bottom flattened to `grouped`
        #expect(r.bottomLeading == base)     // outer kept
        #expect(r.topTrailing == base)       // top untouched
    }

    @Test("An other bubble continued from above flattens only its inner (leading) top corner")
    func otherContinuedAbove_flattensInnerTop() {
        let r = BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: true, groupedBelow: false)
        #expect(r.topLeading == grouped) // inner top flattened to `grouped`
        #expect(r.topTrailing == base)   // outer kept
        #expect(r.bottomLeading == base) // bottom untouched
    }

    /// A bubble laid out at a fixed frame, so `maskingPath` reflects the wiring in
    /// `ChatBubbleView.configure(with:)` rather than a literal passed straight to `radii`.
    private func laidOutBubble(_ message: ChatMessage) -> ChatBubbleView {
        let bubble = ChatBubbleView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        bubble.configure(with: message)
        bubble.layoutIfNeeded()
        return bubble
    }

    @Test("The author run alone does not flatten the corner; only the bubble run does")
    func authorRunAloneLeavesTheCornerUntouched() {
        let authorRunOnly = laidOutBubble(
            ChatMessage(id: "1", text: "hi", sender: .me, isContinuationFromPrevious: true, joinsBubbleAbove: false)
        )
        let neitherRun = laidOutBubble(
            ChatMessage(id: "2", text: "hi", sender: .me)
        )
        #expect(authorRunOnly.maskingPath?.cgPath == neitherRun.maskingPath?.cgPath)

        let bubbleRun = laidOutBubble(
            ChatMessage(id: "3", text: "hi", sender: .me, joinsBubbleAbove: true)
        )
        #expect(bubbleRun.maskingPath?.cgPath != neitherRun.maskingPath?.cgPath)
    }

    @Test("The author run alone does not flatten the bottom corner; only the bubble run does")
    func authorRunAloneLeavesTheBottomCornerUntouched() {
        let authorRunOnly = laidOutBubble(
            ChatMessage(id: "1", text: "hi", sender: .me, isContinuedByNext: true, joinsBubbleBelow: false)
        )
        let neitherRun = laidOutBubble(
            ChatMessage(id: "2", text: "hi", sender: .me)
        )
        #expect(authorRunOnly.maskingPath?.cgPath == neitherRun.maskingPath?.cgPath)

        let bubbleRun = laidOutBubble(
            ChatMessage(id: "3", text: "hi", sender: .me, joinsBubbleBelow: true)
        )
        #expect(bubbleRun.maskingPath?.cgPath != neitherRun.maskingPath?.cgPath)
    }

    @Test("A middle bubble in a self run flattens both inner (trailing) corners")
    func selfMiddleOfRun_flattensBothInner() {
        let r = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: true, groupedBelow: true)
        #expect(r.topTrailing == grouped)
        #expect(r.bottomTrailing == grouped)
        #expect(r.topLeading == base)    // outer kept
        #expect(r.bottomLeading == base)
    }
}

@MainActor
@Suite("ChatMessageCell alignment")
struct ChatMessageCellAlignmentTests {

    /// Returns the bubble's frame *in the content view's* coordinate space. `contentView.subviews[0]`
    /// is the column stack view, which spans the whole row by design and hugs the sender's edge
    /// through its `alignment` — so measuring that against the content view's edges asserts nothing.
    private func laidOutCell(sender: ChatMessage.Sender) -> (cell: ChatMessageCell, bubble: CGRect) {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(with: ChatMessage(id: "1", text: "hi", sender: sender), maxWidth: 250)
        cell.layoutIfNeeded()
        let bubble = cell.bubbleView
        return (cell, bubble.convert(bubble.bounds, to: cell.contentView))
    }

    @Test("A self message hugs the trailing edge")
    func selfMessage_hugsTrailing() {
        let (cell, bubble) = laidOutCell(sender: .me)
        #expect(abs(bubble.maxX - (cell.contentView.bounds.width - 12)) < 0.5)
        #expect(bubble.minX > 12) // does not span the full width
    }

    @Test("An other message hugs the leading edge")
    func otherMessage_hugsLeading() {
        let (cell, bubble) = laidOutCell(sender: .other)
        #expect(abs(bubble.minX - 12) < 0.5)
        #expect(bubble.maxX < cell.contentView.bounds.width - 12)
    }
}

@MainActor
@Suite("Chat bubble deleted and edited rendering")
struct ChatBubbleDeletedTests {

    @Test("A deleted bubble shows the tombstone copy")
    func deletedBubbleShowsCopy() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .deleted("You deleted this message"), sender: .me)
        )
        #expect(text?.string == "You deleted this message")
    }

    @Test("An edited bubble reserves the marker's width after the body, drawn clear")
    func editedBubbleReservesMarker() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me, isEdited: true)
        )
        #expect(text?.string == "hello  Edited")

        // The reservation holds the space; the visible marker is the corner label, so the run in
        // the body must not draw.
        let markerColor = text?.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor
        #expect(markerColor == UIColor.clear)
    }

    @Test("Only a message with a body left to revise carries the marker")
    func markerIsForRevisableBodies() {
        #expect(ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me, isEdited: true)
        ))
        #expect(!ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me)
        ))
        #expect(!ChatBubbleView.showsEditedMarker(
            for: ChatMessage(id: "1", content: .deleted("You deleted this message"), sender: .me, isEdited: true)
        ))
    }

    private static let maxWidth: CGFloat = 250

    /// A bubble laid out through the real cell, so the width cap and self-sizing apply. The cell is
    /// measured the way the collection view measures it — a fixed frame height would stretch the
    /// bubble to fill it and hide the wrap.
    private func laidOutBubble(text: String, isEdited: Bool) -> ChatBubbleView {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        cell.configure(
            with: ChatMessage(id: "1", content: .text(text), sender: .me, isEdited: isEdited),
            maxWidth: Self.maxWidth
        )
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: fitted.height)
        cell.layoutIfNeeded()
        return cell.bubbleView
    }

    private func editedMarker(in bubble: ChatBubbleView) -> UILabel? {
        bubble.subviews.compactMap { $0 as? UILabel }.first { $0.text == EditedMarker.text }
    }

    @Test("The marker sits in the bubble's bottom-trailing corner")
    func markerSitsInTheCorner() throws {
        let bubble = laidOutBubble(text: "hello", isEdited: true)
        let marker = try #require(editedMarker(in: bubble))

        #expect(!marker.isHidden)
        #expect(abs(marker.frame.maxX - (bubble.bounds.width - EditedMarker.trailingInset)) < 0.5)
        #expect(abs(marker.frame.maxY - (bubble.bounds.height - 9)) < 0.5)
    }

    @Test("A last line with room keeps the marker on it, widening the bubble")
    func markerStaysOnALastLineWithRoom() {
        let plain = laidOutBubble(text: "hello", isEdited: false)
        let edited = laidOutBubble(text: "hello", isEdited: true)

        #expect(abs(edited.bounds.height - plain.bounds.height) < 0.5) // still one line
        #expect(edited.bounds.width > plain.bounds.width)              // grew to hold the marker
    }

    @Test("A last line with no room drops the marker onto a line of its own")
    func markerWrapsOffAFullLastLine() throws {
        // Pack short words onto one line until one more would wrap it, so the leftover room on that
        // line is narrower than a word — and narrower still than the marker. Measured off the
        // laid-out bubble rather than off the font, so the insets and the width cap are the real
        // ones.
        let oneLine = laidOutBubble(text: "w", isEdited: false).bounds.height
        var body = "w"
        while laidOutBubble(text: body + " w", isEdited: false).bounds.height == oneLine { body += " w" }

        let plain = laidOutBubble(text: body, isEdited: false)
        let edited = laidOutBubble(text: body, isEdited: true)
        let marker = try #require(editedMarker(in: edited))

        #expect(abs(plain.bounds.height - oneLine) < 0.5)   // the body itself still fits one line
        #expect(edited.bounds.height > plain.bounds.height) // the marker took a line of its own
        #expect(abs(marker.frame.maxX - (edited.bounds.width - EditedMarker.trailingInset)) < 0.5)
    }

    @Test("An unedited bubble is just its body")
    func uneditedBubbleIsPlain() {
        let text = ChatBubbleView.displayText(
            for: ChatMessage(id: "1", content: .text("hello"), sender: .me)
        )
        #expect(text?.string == "hello")
    }

    @Test("A cash row has no bubble text — it uses its own cell")
    func cashRowHasNoBubbleText() {
        let cash = ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: nil, iconURL: nil, isTip: false)
        #expect(ChatBubbleView.displayText(for: ChatMessage(id: "1", content: .cash(cash), sender: .me)) == nil)
    }

    @Test("A deleted message reuses the plain text cell, so a delete reconfigures in place")
    func deletedReusesTextCell() {
        let deleted = ChatItem.message(ChatMessage(id: "1", content: .deleted("Message deleted"), sender: .other))
        let plain = ChatItem.message(ChatMessage(id: "1", text: "hi", sender: .other))
        #expect(deleted.differenceIdentifier == plain.differenceIdentifier)
    }
}

@MainActor
@Suite("Bare emoji bubble")
struct ChatBubbleViewBareTests {

    private func bubble(_ message: ChatMessage) -> ChatBubbleView {
        let view = ChatBubbleView()
        view.configure(with: message)
        view.frame = CGRect(x: 0, y: 0, width: 280, height: 80)
        view.layoutIfNeeded()
        return view
    }

    private func chrome(_ view: ChatBubbleView) -> BubbleBackgroundView {
        view.descendants(of: BubbleBackgroundView.self)[0]
    }

    private func body(_ view: ChatBubbleView, _ text: String) -> UILabel? {
        view.descendants(of: UILabel.self).first { $0.text == text }
    }

    @Test("A bare row drops the opaque base, the wash and the border")
    func bareDropsTheChrome() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(chrome(view).backgroundColor == .clear)
        #expect(!chrome(view).isDrawingBubble)
    }

    @Test("An ordinary row still draws all three")
    func ordinaryKeepsTheChrome() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(chrome(view).backgroundColor != .clear)
        #expect(chrome(view).isDrawingBubble)
    }

    @Test("A bare row keeps its shape mask, so the attention flash stays rounded")
    func bareKeepsTheMask() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(chrome(view).layer.mask != nil)
    }

    @Test("A bare row draws the body large and flush to the view's edge")
    func bareEnlargesAndUninsetsTheBody() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(body(view, "👍")?.font.pointSize == 48)
        #expect(body(view, "👍")?.frame.minX == 0)
    }

    @Test("An ordinary row keeps the body size and the 12pt inset")
    func ordinaryKeepsTheBodyMetrics() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(body(view, "hi")?.font.pointSize == 16)
        #expect(body(view, "hi")?.frame.minX == 12)
    }

    @Test("A bare row has no lift masking path, so nothing casts a bubble-shaped shadow")
    func bareHasNoLiftPath() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        #expect(view.maskingPath == nil)
    }

    @Test("An ordinary row still clips its lift preview to the bubble")
    func ordinaryKeepsItsLiftPath() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        #expect(view.maskingPath != nil)
    }

    @Test("A bare row keeps the Edited marker out of the bubble")
    func bareHidesTheInBubbleMarker() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true, isEdited: true))
        let marker = view.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker?.isHidden == true)
    }

    @Test("An ordinary edited row still draws the marker in the bubble")
    func ordinaryKeepsTheInBubbleMarker() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me, isEdited: true))
        let marker = view.descendants(of: UILabel.self).first { $0.text == EditedMarker.text }
        #expect(marker?.isHidden == false)
    }

    // Inside a live animation context `UIView` answers "backgroundColor" with a real
    // `CABasicAnimation` — that context is what a reconfigure inside a collection-view batch update
    // puts the view in, and the cross-fade this override exists to stop. Asking outside one proves
    // nothing: `UIView` answers `NSNull` there anyway.
    @Test("Inside an animation context the chrome suppresses its own backgroundColor action but not a sublayer's")
    func suppressesBackgroundColorActionOnlyOnItsOwnLayer() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        let background = chrome(view)
        let foreignLayer = CALayer()

        var own: CAAction?
        var foreign: CAAction?
        var plain: CAAction?
        UIView.animate(withDuration: 0.3) {
            own = background.action(for: background.layer, forKey: "backgroundColor")
            foreign = background.action(for: foreignLayer, forKey: "backgroundColor")
            plain = UIView().action(for: foreignLayer, forKey: "backgroundColor")
        }

        // The context is only live if an ordinary view answers with an animation; without that the
        // other two expectations would pass against any implementation.
        #expect(plain is CABasicAnimation)
        #expect(own is NSNull)
        #expect(foreign is CABasicAnimation)
    }

    @Test("Raising with a shape casts the lift shadow along that path")
    func raiseWithShapeCastsTheLiftShadow() {
        let view = UIView()
        let path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: 40, height: 40))
        BubbleBackgroundView.raise(view, shape: path)
        #expect(view.layer.shadowOpacity == 0.65)
        #expect(view.layer.shadowPath != nil)
    }

    @Test("Raising a bare row's clear-backgrounded preview with no shape casts no shadow at all")
    func raiseWithNoShapeCastsNoShadow() {
        let view = UIView()
        BubbleBackgroundView.raise(view, shape: nil)
        #expect(view.layer.shadowOpacity == 0)
        #expect(view.layer.shadowPath == nil)
    }

    @Test("Reconfiguring a bare view with an ordinary message fully restores the bubble chrome")
    func reusedInstance_bareToOrdinary_restoresChrome() {
        let view = bubble(ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true))
        view.configure(with: ChatMessage(id: "2", text: "hi", sender: .me))
        // Verified by deleting it: `layoutIfNeeded()` on its own leaves the body label at its
        // previous inset while the chrome updates, so the pass is asked for explicitly. A recycled
        // cell gets that pass from the collection view invalidating it, which is what this stands in
        // for.
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(chrome(view).isDrawingBubble)
        #expect(chrome(view).backgroundColor != .clear)
        #expect(view.maskingPath != nil)
        #expect(body(view, "hi")?.font.pointSize == 16)
        #expect(body(view, "hi")?.frame.minX == 12)
    }

    @Test("Reconfiguring an ordinary view with a bare message fully reaches the bare state")
    func reusedInstance_ordinaryToBare_reachesBareState() {
        let view = bubble(ChatMessage(id: "1", text: "hi", sender: .me))
        view.configure(with: ChatMessage(id: "2", text: "👍", sender: .me, isEmojiOnly: true))
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(!chrome(view).isDrawingBubble)
        #expect(chrome(view).backgroundColor == .clear)
        #expect(view.maskingPath == nil)
        #expect(body(view, "👍")?.font.pointSize == 48)
        #expect(body(view, "👍")?.frame.minX == 0)
    }
}

@MainActor
@Suite("Edited marker placement")
struct ChatEditedMarkerPlacementTests {

    private func laidOutCell(_ message: ChatMessage) -> ChatMessageCell {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        cell.configure(with: message, maxWidth: 250)
        cell.layoutIfNeeded()
        return cell
    }

    private func visibleMarkers(in cell: ChatMessageCell) -> [UILabel] {
        cell.descendants(of: UILabel.self).filter { $0.text == EditedMarker.text && !$0.isHidden }
    }

    @Test("A bare edited row draws one marker, outside the bubble, and VoiceOver can read it")
    func bareDrawsTheMarkerOnTheMetadataLine() {
        let cell = laidOutCell(
            ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true, isEdited: true)
        )
        let markers = visibleMarkers(in: cell)
        #expect(markers.count == 1)
        #expect(!cell.bubbleView.descendants(of: UILabel.self).contains { $0 === markers.first })
        #expect(markers.first?.isAccessibilityElement == true)
    }

    @Test("An ordinary edited row draws one marker, inside the bubble")
    func ordinaryDrawsTheMarkerInTheBubble() {
        let cell = laidOutCell(ChatMessage(id: "1", text: "hi", sender: .me, isEdited: true))
        let markers = visibleMarkers(in: cell)
        #expect(markers.count == 1)
        #expect(cell.bubbleView.descendants(of: UILabel.self).contains { $0 === markers.first })
    }

    @Test("A bare row that was never edited draws no marker at all")
    func bareUneditedDrawsNothing() {
        let cell = laidOutCell(
            ChatMessage(id: "1", text: "👍", sender: .me, isEmojiOnly: true)
        )
        #expect(visibleMarkers(in: cell).isEmpty)
    }
}
