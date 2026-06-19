//
//  ChatViewControllerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
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

    @Test("Jump-to-bottom button shows only past one viewport from the bottom")
    func jumpButton_visibilityThreshold() {
        #expect(!ChatViewController.shouldShowJumpButton(distanceFromBottom: 0, viewportHeight: 800))
        #expect(!ChatViewController.shouldShowJumpButton(distanceFromBottom: 800, viewportHeight: 800))
        #expect(ChatViewController.shouldShowJumpButton(distanceFromBottom: 801, viewportHeight: 800))
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
