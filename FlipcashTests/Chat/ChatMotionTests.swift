//
//  ChatMotionTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import ChatLayout
import FlipcashCore
@testable import FlipcashUI

/// The transcript's motion language, ported from the design prototype: bubbles scale in from 0.95
/// anchored at their sender's edge (never slide), receipts and corner morphs animate only on
/// in-place updates of the row they already render.
@MainActor
@Suite("Chat motion")
struct ChatMotionTests {

    // MARK: - Layout attributes stay at the library baseline

    // ChatLayout round-trips attribute frames through its keep-at-bottom compensation: reading
    // `.frame` of transformed attributes returns the transformed bounding box, and the offset
    // result is written back. Any transform set on insert/delete attributes is therefore baked
    // into the layout's stored frames — mis-sized rows, unsatisfiable-constraint spam, and the
    // corrupted bookkeeping behind the "missing final attributes" crash. Attributes must stay at
    // the library's default pure fade; entrance motion belongs on the cell
    // (`ChatViewController.playEntranceIfNeeded`). If one of these fails, someone re-added
    // attribute transforms — move the motion to the cell instead.

    private func attributes(width: CGFloat = 390) -> ChatLayoutAttributes {
        let attributes = ChatLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 0, y: 0, width: width, height: 56)
        return attributes
    }

    private var everyRowKind: [ChatItem] {
        [
            .message(ChatMessage(id: "a", text: "hi", sender: .me)),
            .message(ChatMessage(id: "b", text: "hi", sender: .other)),
            .typingIndicator,
            .dateSeparator(id: "sep", text: "Today 12:13 PM"),
        ]
    }

    @Test("Inserted rows keep the library's pure-fade attributes — no transform, ever")
    func insertedAttributes_areLibraryBaseline() {
        let controller = ChatViewController.loaded(items: everyRowKind, animated: false)
        for index in everyRowKind.indices {
            let attributes = attributes()
            controller.initialLayoutAttributesForInsertedItem(
                CollectionViewChatLayout(), at: IndexPath(item: index, section: 0), modifying: attributes, on: .initial
            )
            #expect(attributes.alpha == 0)
            #expect(attributes.transform == .identity)
        }
    }

    @Test("Deleted rows keep the library's pure-fade attributes — no transform, ever")
    func deletedAttributes_areLibraryBaseline() {
        let controller = ChatViewController.loaded(items: everyRowKind, animated: false)
        for index in everyRowKind.indices {
            let attributes = attributes()
            controller.finalLayoutAttributesForDeletedItem(
                CollectionViewChatLayout(), at: IndexPath(item: index, section: 0), modifying: attributes
            )
            #expect(attributes.alpha == 0)
            #expect(attributes.transform == .identity)
        }
    }

    // MARK: - Entrance eligibility

    // Only the trailing run of new rows enters with motion — prepended history and catch-up
    // merges must not replay insertion transitions.

    @Test("Appended rows get entrances")
    func trailingNewIDs_appendedRowsEnter() {
        let old: [ChatItem] = [.text("a"), .text("b")]
        let new: [ChatItem] = [.text("a"), .text("b"), .text("c"), .text("d")]
        #expect(ChatViewController.trailingNewIDs(from: old, to: new) == ["c", "d"])
    }

    @Test("Prepended history gets no entrance")
    func trailingNewIDs_prependedHistoryDoesNotEnter() {
        let old: [ChatItem] = [.text("y"), .text("z")]
        let new: [ChatItem] = (0..<50).map { .text("old-\($0)") } + [.text("y"), .text("z")]
        #expect(ChatViewController.trailingNewIDs(from: old, to: new).isEmpty)
    }

    @Test("An arrival replacing the typing indicator gets an entrance")
    func trailingNewIDs_arrivalReplacingTypingEnters() {
        let old: [ChatItem] = [.text("a"), .typingIndicator]
        let new: [ChatItem] = [.text("a"), .text("b", sender: .other)]
        #expect(ChatViewController.trailingNewIDs(from: old, to: new) == ["b"])
    }

    // MARK: - Cell entrance transform

    // The scale-in runs on the cell (`willDisplay`), composed from this transform.

    @Test("An outgoing bubble's entrance pins its trailing edge")
    func entranceOutgoing_pinsTrailingEdge() {
        let transform = ChatViewController.entranceTransform(
            for: .message(ChatMessage(id: "a", text: "hi", sender: .me)), width: 390
        )
        #expect(abs(transform.a - 0.95) < 0.001)
        // Pinning the trailing edge of a 390pt cell scaled to 0.95 means shifting right by half the
        // shrink: 390 × 0.05 / 2.
        #expect(abs(transform.tx - 9.75) < 0.001)
    }

    @Test("An incoming bubble's entrance pins its leading edge")
    func entranceIncoming_pinsLeadingEdge() {
        let transform = ChatViewController.entranceTransform(
            for: .message(ChatMessage(id: "a", text: "hi", sender: .other)), width: 390
        )
        #expect(abs(transform.a - 0.95) < 0.001)
        #expect(abs(transform.tx - (-9.75)) < 0.001)
    }

    @Test("The typing indicator enters like an incoming bubble")
    func entranceTypingIndicator_pinsLeadingEdge() {
        let transform = ChatViewController.entranceTransform(for: .typingIndicator, width: 390)
        #expect(abs(transform.a - 0.95) < 0.001)
        #expect(transform.tx < 0)
    }

    @Test("A date separator has no entrance — pure fade")
    func entranceDateSeparator_isIdentity() {
        let transform = ChatViewController.entranceTransform(
            for: .dateSeparator(id: "sep", text: "Today 12:13 PM"), width: 390
        )
        #expect(transform == .identity)
    }

    // MARK: - In-place update gate

    @Test("A cell reconfigured for the row it already shows is an in-place update")
    func inPlaceGate_sameRowInWindow() {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(cell)
        window.makeKeyAndVisible()

        let message = ChatMessage(id: "a", text: "hi", sender: .me)
        #expect(!cell.updateColumn(for: message), "first render — not in place")
        #expect(cell.updateColumn(for: message), "same row again, on screen — in place")
        #expect(!cell.updateColumn(for: ChatMessage(id: "b", text: "other row", sender: .me)),
                "different row — not in place")
    }

    @Test("A recycled cell configured for a different row is not an in-place update")
    func inPlaceGate_freshOrOffWindow() {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        let message = ChatMessage(id: "a", text: "hi", sender: .me)
        #expect(!cell.updateColumn(for: message), "never configured — not in place")
        #expect(!cell.updateColumn(for: message), "off-window — nothing visible to animate")
    }

    // MARK: - Corner morph

    @Test("An animated radii change spring-morphs the bubble's mask path")
    func cornerMorph_animatedRadiiChange_addsSpring() {
        let background = BubbleBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        background.apply(fill: .white, radii: BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: false))
        background.layoutIfNeeded()

        background.apply(
            fill: .white,
            radii: BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: true),
            animated: true
        )
        #expect(background.layer.mask?.animation(forKey: "cornerMorph") != nil)
    }

    @Test("A non-animated radii change does not animate, and an animated no-op change does not either")
    func cornerMorph_notAnimatedWithoutChangeOrFlag() {
        let background = BubbleBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        let standalone = BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: false)
        background.apply(fill: .white, radii: standalone)
        background.layoutIfNeeded()

        // Same radii, animated: nothing to morph.
        background.apply(fill: .white, radii: standalone, animated: true)
        #expect(background.layer.mask?.animation(forKey: "cornerMorph") == nil)

        // Changed radii, not animated (a recycled cell rendering a different row).
        background.apply(fill: .white, radii: BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: true, groupedBelow: false))
        #expect(background.layer.mask?.animation(forKey: "cornerMorph") == nil)
    }

    @Test("A recycled cell's direct apply drops an in-flight morph so the old row's shape can't play over the new row")
    func cornerMorph_recycledCellDropsInFlightMorph() {
        let background = BubbleBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        background.apply(fill: .white, radii: BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: false))
        background.layoutIfNeeded()
        background.apply(
            fill: .white,
            radii: BubbleBackgroundView.radii(isFromSelf: true, groupedAbove: false, groupedBelow: true),
            animated: true
        )
        #expect(background.layer.mask?.animation(forKey: "cornerMorph") != nil)

        // Recycled for a different row while the morph is still running: the direct path snaps.
        background.apply(fill: .white, radii: BubbleBackgroundView.radii(isFromSelf: false, groupedAbove: false, groupedBelow: false))
        #expect(background.layer.mask?.animation(forKey: "cornerMorph") == nil)
    }
}
