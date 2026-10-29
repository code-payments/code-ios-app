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
        #expect(menu(controller, at: 0) == nil)
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

    @Test("Report renders last, and is marked destructive")
    func reportIsOfferedAndDestructive() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", text: "hi", sender: .other, actions: [.copy, .reply, .report]))
        ])
        #expect(titles(menu(controller, at: 0)) == ["Copy", "Reply", "Report"])

        guard let report = menu(controller, at: 0)?.children
            .compactMap({ $0 as? UIAction })
            .first(where: { $0.title == "Report" }) else {
            Issue.record("expected a Report action")
            return
        }
        #expect(report.attributes.contains(.destructive))
    }

    @Test("Report reports the row's id to the screen")
    func reportNotifies() {
        let controller = loadedController([
            .message(ChatMessage(id: "row-9", text: "hi", sender: .other, actions: [.report]))
        ])
        var notified: [(String, MessageCapability)] = []
        controller.onMessageAction = { notified.append(($0, $1)) }

        guard let report = menu(controller, at: 0)?.children.first as? UIAction else {
            Issue.record("expected a Report action")
            return
        }
        report.performWithSender(nil, target: nil)

        #expect(notified.map(\.0) == ["row-9"])
        #expect(notified.map(\.1) == [.report])
    }

    @Test("A deleted placeholder offers no menu")
    func tombstoneOffersNoMenu() {
        let controller = loadedController([
            .message(ChatMessage(id: "1", content: .deleted("This message was deleted"), sender: .other))
        ])
        #expect(menu(controller, at: 0) == nil)
    }
}

@MainActor
@Suite("Long-press lift menu rows")
struct LiftMenuRowsTests {

    private func controller(actions: [MessageCapability]) -> ChatViewController {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: [.message(ChatMessage(id: "1", text: "hi", sender: .other, actions: actions))])
        return controller
    }

    @Test("The lift menu carries the moderation rows, which the context menu nests in an inline section")
    func liftRowsIncludeModeration() {
        let rows = controller(actions: [.copy, .reply, .forward, .report, .silence, .remove])
            .liftMenuActions(for: ChatMessage(id: "1", text: "hi", sender: .other, actions: [.copy, .reply, .forward, .report, .silence, .remove]))
        #expect(rows.map(\.title).count == 6)
        #expect(rows.map(\.title).first == "Copy")
        #expect(rows.map(\.title).contains { $0.hasPrefix("Restrict") })
        #expect(rows.map(\.title).contains { $0.hasPrefix("Remove") })
    }

    @Test("A divider sets moderation apart from Report, and Remove does not add another")
    func dividersAroundModeration() {
        let report = UIAction(title: "Report", attributes: .destructive) { _ in }
        let silence = UIAction(title: "Silence") { _ in }
        let remove = UIAction(title: "Remove", attributes: .destructive) { _ in }
        let copy = UIAction(title: "Copy") { _ in }
        let rows = [copy, report, silence, remove]
        let flat = MessageMenuView.size(for: [copy, report])
        // Two dividers (before Report, before Silence) over two extra rows.
        #expect(MessageMenuView.size(for: rows).height - flat.height == CGFloat(2 * 44 + 13))
    }
}

@MainActor
@Suite("Moderation row titles")
struct ModerationRowTitleTests {
    @Test("Restrict and Remove name the sender with no ellipsis")
    func titles() {
        #expect(MessageCapability.silence.menuTitle(naming: "Ada") == "Restrict Ada")
        #expect(MessageCapability.remove.menuTitle(naming: "Ada") == "Remove Ada")
    }
}
