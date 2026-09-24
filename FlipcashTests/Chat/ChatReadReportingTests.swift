//
//  ChatReadReportingTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController read reporting")
struct ChatReadReportingTests {

    private func message(_ id: UInt64, _ sender: ChatMessage.Sender = .other) -> ChatItem {
        .message(ChatMessage(id: "msg-\(id)", serverID: MessageID(value: id), text: "message \(id)", sender: sender))
    }

    /// Messages 1...`count`, with the unread divider under `dividerAfter` when set.
    private func transcript(count: UInt64, dividerAfter: UInt64? = nil, sender: ChatMessage.Sender = .other) -> [ChatItem] {
        (1...count).flatMap { id -> [ChatItem] in
            id == dividerAfter ? [message(id, sender), .unreadDivider(count: Int(count - id))] : [message(id, sender)]
        }
    }

    private func host(_ controller: ChatViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    /// Lets layout, self-sizing, and the queued positioning turns run.
    private func settle(_ controller: ChatViewController) async {
        for _ in 0..<8 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    @Test("Nothing is reported before the opening scroll lands")
    func silentBeforePositioning() {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 40, dividerAfter: 10))
        controller.view.layoutIfNeeded()

        #expect(reported.isEmpty)
    }

    @Test("A divider open reports the rows it lands on, never the bottom it laid out at first")
    func dividerOpenReportsOnlyRowsOnScreen() async throws {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 40, dividerAfter: 10))
        await settle(controller)

        let seen = try #require(reported.last)
        #expect(seen > MessageID(value: 10))
        #expect(seen < MessageID(value: 40), "the bottom row was reported read at \(seen) though the open landed on the divider")
    }

    @Test("An open without a divider lands at the bottom and reports the newest row")
    func bottomOpenReportsNewest() async {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 40))
        await settle(controller)

        #expect(reported == [MessageID(value: 40)])
    }

    @Test("The viewer's own messages are never reported")
    func ownMessagesAreNotReported() async {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 20, sender: .me))
        await settle(controller)

        #expect(reported.isEmpty)
    }

    @Test("An arrival at the bottom is reported without a scroll")
    func arrivalAtBottomIsReported() async {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 20))
        await settle(controller)
        controller.update(items: transcript(count: 21))
        await settle(controller)

        #expect(reported.last == MessageID(value: 21))
    }

    @Test("With reporting off, nothing is reported until it turns back on")
    func reportingOffHoldsReports() async {
        let controller = ChatViewController()
        var reported: [MessageID] = []
        controller.onMessagesSeen = { reported.append($0) }
        controller.reportsReads = false
        let window = host(controller)
        defer { window.isHidden = true }

        controller.update(items: transcript(count: 20))
        await settle(controller)
        #expect(reported.isEmpty)

        controller.reportsReads = true
        await settle(controller)
        #expect(reported == [MessageID(value: 20)])
    }

    @Test("Any part of a row on screen counts as seen")
    func slightestOverlapCounts() {
        let visible = CGRect(x: 0, y: 100, width: 390, height: 600)
        #expect(ChatViewController.isSeen(CGRect(x: 0, y: 99, width: 390, height: 2), in: visible))
        #expect(ChatViewController.isSeen(CGRect(x: 0, y: 699, width: 390, height: 40), in: visible))
        #expect(!ChatViewController.isSeen(CGRect(x: 0, y: 60, width: 390, height: 40), in: visible))
        #expect(!ChatViewController.isSeen(CGRect(x: 0, y: 700, width: 390, height: 40), in: visible))
    }
}
