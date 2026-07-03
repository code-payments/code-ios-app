//
//  ChatMessageCopyTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController copy menu")
struct ChatMessageCopyTests {

    private func loadedController(_ items: [ChatItem]) -> ChatViewController {
        .loaded(items: items)
    }

    private func configuration(_ controller: ChatViewController, at index: Int) -> UIContextMenuConfiguration? {
        controller.collectionView(
            controller.collectionView,
            contextMenuConfigurationForItemAt: IndexPath(item: index, section: 0),
            point: .zero
        )
    }

    /// Drives the close of the menu. A `nil` animator runs the controller's cleanup synchronously.
    private func closeMenu(_ controller: ChatViewController) {
        controller.collectionView(
            controller.collectionView,
            willEndContextMenuInteraction: UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil),
            animator: nil
        )
    }

    @Test("A text message offers a context menu")
    func textMessage_offersMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "a", text: "Hello there", sender: .other)),
        ])
        #expect(configuration(controller, at: 0) != nil)
    }

    @Test("The configuration identifier encodes the section and item, so the preview can resolve the cell")
    func configuration_identifierEncodesIndexPath() {
        let controller = loadedController([
            .message(ChatMessage(id: "a", text: "first", sender: .me)),
            .message(ChatMessage(id: "b", text: "second", sender: .other)),
        ])
        #expect(configuration(controller, at: 1)?.identifier as? String == "0|1")
    }

    @Test("A cash card offers no context menu — nothing to copy")
    func cashMessage_offersNoMenu() {
        let cash = ChatMessage(
            id: "cash",
            content: .cash(ChatCashContent(amount: "$5.00", token: "Cash")),
            sender: .me
        )
        let controller = loadedController([.message(cash)])
        #expect(configuration(controller, at: 0) == nil)
    }

    @Test("A date separator offers no context menu")
    func dateSeparator_offersNoMenu() {
        let controller = loadedController([.dateSeparator(id: "sep", text: "Today 12:13 PM")])
        #expect(configuration(controller, at: 0) == nil)
    }

    @Test("A message arriving while the menu is open is held, not applied")
    func openMenu_defersPushedUpdate() {
        let controller = loadedController([.message(ChatMessage(id: "a", text: "Hello", sender: .me))])
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 1)

        // Open the menu, then a new message is pushed while it's up.
        #expect(configuration(controller, at: 0) != nil)
        controller.update(items: [
            .message(ChatMessage(id: "a", text: "Hello", sender: .me)),
            .message(ChatMessage(id: "b", text: "Just arrived", sender: .other)),
        ])

        // Held — the transcript doesn't reflow out from under the lifted preview.
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 1)
    }

    @Test("Closing the menu applies the update that arrived while it was open")
    func closingMenu_appliesDeferredUpdate() {
        let controller = loadedController([.message(ChatMessage(id: "a", text: "Hello", sender: .me))])
        #expect(configuration(controller, at: 0) != nil)
        controller.update(items: [
            .message(ChatMessage(id: "a", text: "Hello", sender: .me)),
            .message(ChatMessage(id: "b", text: "Just arrived", sender: .other)),
        ])
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 1) // held

        closeMenu(controller)

        #expect(controller.collectionView.numberOfItems(inSection: 0) == 2) // applied
    }
}
