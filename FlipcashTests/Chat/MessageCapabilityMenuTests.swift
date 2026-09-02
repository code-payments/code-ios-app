//
//  MessageCapabilityMenuTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController action menu")
struct MessageCapabilityMenuTests {

    private func loadedController(_ items: [ChatItem]) -> ChatViewController {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: items)
        return controller
    }

    private func configuration(_ controller: ChatViewController, at index: Int) -> UIContextMenuConfiguration? {
        controller.collectionView(
            controller.collectionView,
            contextMenuConfigurationForItemAt: IndexPath(item: index, section: 0),
            point: .zero
        )
    }

    private func menu(_ controller: ChatViewController, at index: Int) -> UIMenu? {
        controller.contextMenu(forItemAt: IndexPath(item: index, section: 0))
    }

    private func titles(_ menu: UIMenu?) -> [String] {
        (menu?.children ?? []).compactMap { ($0 as? UIAction)?.title }
    }

    @Test("The menu renders exactly the actions the message carries, in order")
    func menuMatchesActions() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .me, actions: [.copy, .edit, .delete]))
        ])
        #expect(titles(menu(controller, at: 0)) == ["Copy", "Edit", "Delete"])
    }

    @Test("A message with no actions offers no menu")
    func noActionsMeansNoMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .other, actions: []))
        ])
        #expect(configuration(controller, at: 0) == nil)
    }

    @Test("Delete is marked destructive")
    func deleteIsDestructive() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .me, actions: [.copy, .delete]))
        ])
        guard let delete = menu(controller, at: 0)?.children
            .compactMap({ $0 as? UIAction })
            .first(where: { $0.title == "Delete" }) else {
            Issue.record("expected a Delete action")
            return
        }
        #expect(delete.attributes.contains(.destructive))
    }

    @Test("Copy writes the body to the pasteboard without notifying the screen")
    func copyStaysLocal() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "copy me", sender: .me, actions: [.copy]))
        ])
        var notified: [(String, MessageCapability)] = []
        controller.onMessageAction = { notified.append(($0, $1)) }

        guard let copy = menu(controller, at: 0)?.children.first as? UIAction else {
            Issue.record("expected a Copy action")
            return
        }
        copy.performWithSender(nil, target: nil)

        #expect(UIPasteboard.general.string == "copy me")
        #expect(notified.isEmpty)
    }

    @Test("Edit and Delete report the row's id to the screen")
    func editAndDeleteNotify() {
        let controller = loadedController([
            .message(ChatMessage(id: "row-7", text: "hi", sender: .me, actions: [.edit, .delete]))
        ])
        var notified: [(String, MessageCapability)] = []
        controller.onMessageAction = { notified.append(($0, $1)) }

        guard let children = menu(controller, at: 0)?.children else {
            Issue.record("expected a menu")
            return
        }
        for action in children.compactMap({ $0 as? UIAction }) {
            action.performWithSender(nil, target: nil)
        }

        #expect(notified.map(\.0) == ["row-7", "row-7"])
        #expect(notified.map(\.1) == [.edit, .delete])
    }

    @Test("A deleted placeholder offers no menu")
    func tombstoneOffersNoMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", content: .deleted("This message was deleted"), sender: .other))
        ])
        #expect(configuration(controller, at: 0) == nil)
    }
}
