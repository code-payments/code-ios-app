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

    // MARK: - Inserted / deleted cell attributes

    private func attributes(width: CGFloat = 390) -> ChatLayoutAttributes {
        let attributes = ChatLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.frame = CGRect(x: 0, y: 0, width: width, height: 56)
        return attributes
    }

    private func controller(items: [ChatItem]) -> ChatViewController {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: items, animated: false)
        return controller
    }

    @Test("An inserted outgoing bubble scales in from its trailing edge")
    func insertedOutgoing_scalesFromTrailingEdge() {
        let controller = controller(items: [.message(ChatMessage(id: "a", text: "hi", sender: .me))])
        let attributes = attributes()
        controller.initialLayoutAttributesForInsertedItem(
            CollectionViewChatLayout(), at: IndexPath(item: 0, section: 0), modifying: attributes, on: .initial
        )
        #expect(attributes.alpha == 0)
        #expect(abs(attributes.transform.a - 0.95) < 0.001)
        // Pinning the trailing edge of a 390pt cell scaled to 0.95 means shifting right by half the
        // shrink: 390 × 0.05 / 2.
        #expect(abs(attributes.transform.tx - 9.75) < 0.001)
    }

    @Test("An inserted incoming bubble scales in from its leading edge")
    func insertedIncoming_scalesFromLeadingEdge() {
        let controller = controller(items: [.message(ChatMessage(id: "a", text: "hi", sender: .other))])
        let attributes = attributes()
        controller.initialLayoutAttributesForInsertedItem(
            CollectionViewChatLayout(), at: IndexPath(item: 0, section: 0), modifying: attributes, on: .initial
        )
        #expect(attributes.alpha == 0)
        #expect(abs(attributes.transform.a - 0.95) < 0.001)
        #expect(abs(attributes.transform.tx - (-9.75)) < 0.001)
    }

    @Test("An inserted date separator only fades — no scale, no slide")
    func insertedDateSeparator_onlyFades() {
        let controller = controller(items: [.dateSeparator(id: "sep", text: "Today 12:13 PM")])
        let attributes = attributes()
        controller.initialLayoutAttributesForInsertedItem(
            CollectionViewChatLayout(), at: IndexPath(item: 0, section: 0), modifying: attributes, on: .initial
        )
        #expect(attributes.alpha == 0)
        #expect(attributes.transform == .identity)
    }

    @Test("The typing indicator enters like an incoming bubble")
    func insertedTypingIndicator_scalesFromLeadingEdge() {
        let controller = controller(items: [.typingIndicator])
        let attributes = attributes()
        controller.initialLayoutAttributesForInsertedItem(
            CollectionViewChatLayout(), at: IndexPath(item: 0, section: 0), modifying: attributes, on: .initial
        )
        #expect(attributes.alpha == 0)
        #expect(abs(attributes.transform.a - 0.95) < 0.001)
        #expect(attributes.transform.tx < 0)
    }

    @Test("A deleted typing indicator exits like an incoming bubble")
    func deletedTypingIndicator_scalesOutToLeadingEdge() {
        let controller = controller(items: [.typingIndicator])
        let attributes = attributes()
        controller.finalLayoutAttributesForDeletedItem(
            CollectionViewChatLayout(), at: IndexPath(item: 0, section: 0), modifying: attributes
        )
        #expect(attributes.alpha == 0)
        #expect(abs(attributes.transform.a - 0.95) < 0.001)
        #expect(attributes.transform.tx < 0)
    }

    // MARK: - In-place update gate

    @Test("A cell reconfigured for the row it already shows is an in-place update")
    func inPlaceGate_sameRowInWindow() {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.addSubview(cell)
        window.makeKeyAndVisible()

        let message = ChatMessage(id: "a", text: "hi", sender: .me)
        cell.configure(with: message, maxWidth: 300)
        #expect(cell.isInPlaceUpdate(for: message))
        #expect(!cell.isInPlaceUpdate(for: ChatMessage(id: "b", text: "other row", sender: .me)))
    }

    @Test("A recycled cell configured for a different row is not an in-place update")
    func inPlaceGate_freshOrOffWindow() {
        let cell = ChatMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 56))
        let message = ChatMessage(id: "a", text: "hi", sender: .me)
        #expect(!cell.isInPlaceUpdate(for: message), "never configured — not in place")
        cell.configure(with: message, maxWidth: 300)
        #expect(!cell.isInPlaceUpdate(for: message), "off-window — nothing visible to animate")
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
}
