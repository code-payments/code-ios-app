//
//  ChatViewControllerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

@MainActor
@Suite("ChatViewController rendering")
struct ChatViewControllerTests {

    private func item(_ i: Int, _ sender: ChatMessage.Sender = .me) -> ChatItem {
        .message(ChatMessage(id: "msg-\(i)", text: "message \(i)", sender: sender))
    }

    @Test("Update renders one item per message")
    func update_rendersOneItemPerMessage() {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: (0..<12).map { item($0, $0.isMultiple(of: 2) ? .me : .other) })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 12)
    }

    @Test("A later update replaces the previous transcript")
    func update_replacesPreviousTranscript() {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: (0..<5).map { item($0) })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 5)
        controller.update(items: (0..<3).map { item(100 + $0, .other) })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 3)
    }

    @Test("Items pushed before the view loads are applied once it loads")
    func update_beforeViewLoads_appliesOnLoad() {
        let controller = ChatViewController()
        controller.update(items: (0..<4).map { item($0) })
        controller.loadViewIfNeeded()
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 4)
    }

    @Test("Prepending an older page grows the transcript")
    func update_prependOlderPage_growsTranscript() {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        controller.update(items: (80..<100).map { item($0) })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 20)
        controller.update(items: (60..<100).map { item($0) })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 40)
    }

    @Test("Appending a message grows the transcript by one")
    func update_appendMessage_growsByOne() {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        let base = (0..<10).map { item($0) }
        controller.update(items: base)
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 10)
        controller.update(items: base + [item(99, .other)])
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 11)
    }

    @Test("A send's receipt migration + grouping flip + insert applies as one batch")
    func update_receiptMigrationWithInsert_appliesInOneBatch() async {
        // A new own message updates the previous row (receipt migrates off it, isContinuedByNext
        // flips) in the same push that inserts the new row. On a live window this must apply as a
        // single batch update — reconfigure + insert together — without throwing or dropping rows.
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let before = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .message(ChatMessage(id: "sent-1", text: "first send", sender: .me, receipt: "Delivered")),
        ]
        controller.update(items: before)
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }

        let after = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .message(ChatMessage(id: "sent-1", text: "first send", sender: .me, isContinuedByNext: true)),
            .message(ChatMessage(id: "sent-2", text: "second send", sender: .me, isContinuationFromPrevious: true, receipt: "Delivered")),
        ]
        controller.update(items: after)
        #expect(controller.collectionView.numberOfItems(inSection: 0) == after.count)
    }

    @Test("An arrival while typing (update + delete + insert) applies as one batch")
    func update_arrivalWhileTyping_appliesInOneBatch() async {
        // The riskiest merged shape: the typing indicator deletes, the reply inserts at the same
        // position, and the previous row reconfigures — all in one batch on a live window.
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let before: [ChatItem] = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .message(ChatMessage(id: "them-1", text: "typing next", sender: .other)),
            .typingIndicator,
        ]
        controller.update(items: before)
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }

        let after: [ChatItem] = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .message(ChatMessage(id: "them-1", text: "typing next", sender: .other, isContinuedByNext: true)),
            .message(ChatMessage(id: "them-2", text: "the reply", sender: .other, isContinuationFromPrevious: true)),
        ]
        controller.update(items: after)
        #expect(controller.collectionView.numberOfItems(inSection: 0) == after.count)
    }

    @Test("Opens at the bottom (newest message) on first layout")
    func opensAtBottom() async {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.update(items: (0..<40).map {
            item($0, $0.isMultiple(of: 2) ? .me : .other)
        })

        // Let layout and self-sizing settle across a few main-runloop turns.
        for _ in 0..<6 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }

        let collectionView = controller.collectionView!
        let maxOffset = max(0, collectionView.contentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom)
        #expect(maxOffset > 100) // content must exceed the viewport for "bottom" to mean anything
        #expect(abs(collectionView.contentOffset.y - maxOffset) < 2,
                "should open at the bottom — offset \(collectionView.contentOffset.y) vs max \(maxOffset)")
    }
}
