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
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: items)
        return controller
    }

    private func menu(_ controller: ChatViewController, at index: Int) -> UIMenu? {
        controller.contextMenu(forItemAt: IndexPath(item: index, section: 0))
    }

    /// A controller in a window showing `message`, with its row lifted as a long press lifts it. The
    /// window gives the row a cell to lift, and the few rendered frames give the lift something to
    /// snapshot.
    private func liftedController(_ message: ChatMessage) async -> (ChatViewController, UIWindow) {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: [.message(message)], animated: false)
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
        #expect(controller.beginLift(for: message, in: controller.view) != nil)
        return (controller, window)
    }

    @Test("A text message offers a context menu")
    func textMessage_offersMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "a", text: "Hello there", sender: .other, actions: [.copy])),
        ])
        #expect(menu(controller, at: 0) != nil)
    }

    @Test("A cash card offers no context menu — nothing to copy")
    func cashMessage_offersNoMenu() {
        let cash = ChatMessage(
            id: "cash",
            content: .cash(ChatCashContent(amount: "$5.00", token: "Cash")),
            sender: .me
        )
        let controller = loadedController([.message(cash)])
        #expect(menu(controller, at: 0) == nil)
    }

    @Test("A date separator offers no context menu")
    func dateSeparator_offersNoMenu() {
        let controller = loadedController([.dateSeparator(id: "sep", text: "Today 12:13 PM")])
        #expect(menu(controller, at: 0) == nil)
    }

    @Test("A message arriving while a row is lifted is held, not applied")
    func lift_defersPushedUpdate() async {
        let hello = ChatMessage(id: "a", text: "Hello", sender: .me, actions: [.copy])
        // Lift the row, then a new message is pushed while it's up.
        let (controller, window) = await liftedController(hello)
        defer { window.isHidden = true }
        controller.update(items: [
            .message(ChatMessage(id: "a", text: "Hello", sender: .me, actions: [.copy])),
            .message(ChatMessage(id: "b", text: "Just arrived", sender: .other, actions: [.copy])),
        ])

        // Held — the transcript doesn't reflow out from under the lift.
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 1)
    }

    @Test("Ending the lift applies the update that arrived while it was up")
    func endingLift_appliesDeferredUpdate() async {
        let hello = ChatMessage(id: "a", text: "Hello", sender: .me, actions: [.copy])
        let (controller, window) = await liftedController(hello)
        defer { window.isHidden = true }
        controller.update(items: [
            .message(ChatMessage(id: "a", text: "Hello", sender: .me, actions: [.copy])),
            .message(ChatMessage(id: "b", text: "Just arrived", sender: .other, actions: [.copy])),
        ])
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 1) // held

        controller.endLift()

        #expect(controller.collectionView.numberOfItems(inSection: 0) == 2) // applied
    }
}
