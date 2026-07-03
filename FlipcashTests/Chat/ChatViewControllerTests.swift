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
        .text("msg-\(i)", sender: sender)
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
        let (controller, window) = ChatViewController.windowed()
        defer { _ = window }

        let before = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .text("sent-1", receipt: "Delivered"),
        ]
        controller.update(items: before)
        await controller.settle()

        let after = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .text("sent-1", continuedByNext: true),
            .text("sent-2", continuationFromPrevious: true, receipt: "Delivered"),
        ]
        controller.update(items: after)
        #expect(controller.collectionView.numberOfItems(inSection: 0) == after.count)
    }

    @Test("An arrival while typing (update + delete + insert) applies as one batch")
    func update_arrivalWhileTyping_appliesInOneBatch() async {
        // The riskiest merged shape: the typing indicator deletes, the reply inserts at the same
        // position, and the previous row reconfigures — all in one batch on a live window.
        let (controller, window) = ChatViewController.windowed()
        defer { _ = window }

        let before: [ChatItem] = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .text("them-1", sender: .other),
            .typingIndicator,
        ]
        controller.update(items: before)
        await controller.settle()

        let after: [ChatItem] = (0..<8).map { item($0, $0.isMultiple(of: 2) ? .me : .other) } + [
            .text("them-1", sender: .other, continuedByNext: true),
            .text("them-2", sender: .other, continuationFromPrevious: true),
        ]
        controller.update(items: after)
        #expect(controller.collectionView.numberOfItems(inSection: 0) == after.count)
    }

    // MARK: - Animation fence (regression: the missing-final-attributes crash)

    // ChatLayout's `restoreContentOffset` deliberately answers attribute queries with nil while
    // it re-anchors. An inset write or transcript push overlapping a settling batch spring is
    // how that nil met UIKit's animated-bounds-change cross-fade and threw
    // "missing final attributes for cell" (the repro: Send with a hardware keyboard — the
    // composer collapse's inset change replayed mid-animation). These pin the fence behavior:
    // work arriving mid-transaction defers, then replays once the springs settle.

    @Test("An inset arriving mid-animated-update is deferred, then applied once it settles")
    func setBottomInset_duringAnimatedUpdate_deferredThenApplied() async {
        let (controller, window) = ChatViewController.windowed()
        defer { _ = window }
        let base = (0..<12).map { item($0, $0.isMultiple(of: 2) ? .me : .other) }
        controller.update(items: base)
        await controller.settle(turns: 6)

        controller.update(items: base + [item(99)]) // animated batch — the fence is up
        controller.setBottomInset(100)
        // 112 = 100 + the transcript's 12pt bottom content padding.
        #expect(controller.collectionView.contentInset.bottom != 112,
                "the write must not land while the batch's spring settles")
        await controller.settle(until: { controller.collectionView.contentInset.bottom == 112 })
        #expect(controller.collectionView.contentInset.bottom == 112)
    }

    @Test("A push arriving mid-animated-update is deferred and the latest wins")
    func update_duringAnimatedUpdate_deferredLatestWins() async {
        let (controller, window) = ChatViewController.windowed()
        defer { _ = window }
        let base = (0..<10).map { item($0) }
        controller.update(items: base)
        await controller.settle(turns: 6)

        controller.update(items: base + [item(50)])                     // batch A — fence up
        controller.update(items: base + [item(50), item(51)])           // held
        controller.update(items: base + [item(50), item(51), item(52)]) // held — latest wins
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 11,
                "only batch A applies while its spring settles")
        await controller.settle(until: { controller.collectionView.numberOfItems(inSection: 0) == 13 })
        #expect(controller.collectionView.numberOfItems(inSection: 0) == 13)
    }

    @Test("Opens at the bottom (newest message) on first layout")
    func opensAtBottom() async {
        let (controller, window) = ChatViewController.windowed()
        defer { _ = window }

        controller.update(items: (0..<40).map {
            item($0, $0.isMultiple(of: 2) ? .me : .other)
        })
        await controller.settle(turns: 6)

        let collectionView = controller.collectionView!
        let maxOffset = max(0, collectionView.contentSize.height
            - collectionView.bounds.height
            + collectionView.adjustedContentInset.bottom)
        #expect(maxOffset > 100) // content must exceed the viewport for "bottom" to mean anything
        #expect(abs(collectionView.contentOffset.y - maxOffset) < 2,
                "should open at the bottom — offset \(collectionView.contentOffset.y) vs max \(maxOffset)")
    }

    @Test("A link-bearing message dequeues the tappable link cell; plain text uses the label cell")
    func linkMessage_usesLinkCell() {
        let controller = ChatViewController()
        controller.loadViewIfNeeded()
        let link = ChatMessage(id: "link", text: "see https://apple.com", sender: .me,
                               linkPreview: LinkPreview(url: URL(string: "https://apple.com")!))
        let plain = ChatMessage(id: "plain", text: "hello there", sender: .me)
        controller.update(items: [.message(link), .message(plain)])

        let linkCell = controller.collectionView(controller.collectionView, cellForItemAt: IndexPath(item: 0, section: 0))
        let plainCell = controller.collectionView(controller.collectionView, cellForItemAt: IndexPath(item: 1, section: 0))
        #expect(linkCell is ChatLinkMessageCell)
        #expect(plainCell is ChatMessageCell)
    }
}
