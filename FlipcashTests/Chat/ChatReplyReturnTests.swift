//
//  ChatReplyReturnTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// The jump button walking back through reply-quote taps before it goes to the bottom.
@MainActor
@Suite("Chat reply return")
struct ChatReplyReturnTests {

    private func item(_ i: Int) -> ChatItem {
        .message(ChatMessage(id: "msg-\(i)", text: "message \(i)", sender: i.isMultiple(of: 2) ? .me : .other))
    }

    /// A transcript of 40 rows in a window, settled at its newest message.
    private func host(items: [ChatItem]? = nil) async -> (ChatViewController, UIWindow) {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: items ?? (0..<40).map(item))
        for _ in 0..<6 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
        return (controller, window)
    }

    /// The ids of the rows flashing now.
    private func flashing(_ controller: ChatViewController) -> [Int] {
        controller.collectionView.indexPathsForVisibleItems.compactMap { indexPath in
            guard let cell = controller.collectionView.cellForItem(at: indexPath) as? ChatMessageCell,
                  cell.bubbleView.isFlashingAttention else { return nil }
            return indexPath.item
        }
    }

    /// Taps the quote in `origin` that points at `quoted`, as the screen does: push, then jump.
    private func tapQuote(_ controller: ChatViewController, quoted: Int, in origin: Int) {
        controller.quoteTapped("msg-\(quoted)", in: "msg-\(origin)")
        controller.scrollToMessage(id: "msg-\(quoted)")
    }

    @Test("A quote tap pushes its origin and shows the jump button")
    func quoteTap_pushesOriginAndShowsButton() async {
        let (controller, window) = await host()
        var visible = false
        controller.onJumpButtonVisibilityChange = { visible = $0 }
        tapQuote(controller, quoted: 5, in: 38)
        #expect(controller.replyReturns.origins == ["msg-38"])
        #expect(visible)
        _ = window
    }

    @Test("Tapping two quotes in the same message pushes it once")
    func quoteTap_sameOriginTwice_pushesOnce() async {
        let (controller, window) = await host()
        tapQuote(controller, quoted: 5, in: 38)
        tapQuote(controller, quoted: 6, in: 38)
        #expect(controller.replyReturns.origins == ["msg-38"])
        _ = window
    }

    @Test("The jump button walks back through a quote chain, newest origin first, flashing each")
    func jump_popsToEachOriginThenBottom() async {
        let (controller, window) = await host()
        tapQuote(controller, quoted: 20, in: 38)
        tapQuote(controller, quoted: 3, in: 20)

        controller.jumpFromJumpButton()
        #expect(flashing(controller) == [20])
        #expect(controller.replyReturns.origins == ["msg-38"])

        controller.jumpFromJumpButton()
        #expect(flashing(controller).contains(38))
        #expect(controller.replyReturns.isEmpty)
        _ = window
    }

    @Test("An origin gone from the transcript is skipped for the one under it")
    func jump_skipsMissingOrigin() async {
        let (controller, window) = await host()
        tapQuote(controller, quoted: 20, in: 36)
        tapQuote(controller, quoted: 3, in: 20)
        controller.update(items: (0..<40).filter { $0 != 20 }.map(item))
        controller.view.layoutIfNeeded()

        controller.jumpFromJumpButton()
        #expect(controller.replyReturns.isEmpty)
        #expect(flashing(controller).contains(35), "msg-36 sits at index 35 once msg-20 is gone")
        _ = window
    }

    @Test("A programmatic jump that lands with the origin on screen keeps it")
    func programmaticJump_doesNotDrop() async {
        let (controller, window) = await host()
        tapQuote(controller, quoted: 20, in: 22)
        #expect(controller.replyReturns.origins == ["msg-22"])
        _ = window
    }

    @Test("A quote jump between rows near the bottom keeps the origin and shows the button")
    func quoteJumpNearBottom_keepsOrigin() async {
        let (controller, window) = await host()
        var visible = false
        controller.onJumpButtonVisibilityChange = { visible = $0 }
        tapQuote(controller, quoted: 38, in: 39)
        #expect(controller.replyReturns.origins == ["msg-39"])
        #expect(visible)
        _ = window
    }

    @Test("Returning to an origin near the bottom keeps the origins under it")
    func popToOriginNearBottom_keepsRest() async {
        let (controller, window) = await host()
        var visible = false
        controller.onJumpButtonVisibilityChange = { visible = $0 }
        tapQuote(controller, quoted: 38, in: 39)
        tapQuote(controller, quoted: 20, in: 38)
        try? await Task.sleep(for: .milliseconds(800))
        controller.jumpFromJumpButton()
        try? await Task.sleep(for: .milliseconds(800))
        #expect(controller.replyReturns.origins == ["msg-39"])
        #expect(visible)
        _ = window
    }

    @Test("Reaching the bottom clears every origin and hides the button")
    func reachingBottom_clears() async {
        let (controller, window) = await host()
        var visible = false
        controller.onJumpButtonVisibilityChange = { visible = $0 }
        tapQuote(controller, quoted: 3, in: 20)
        tapQuote(controller, quoted: 1, in: 3)
        controller.scrollToBottom(animated: false)
        #expect(controller.replyReturns.isEmpty)
        #expect(!visible)
        _ = window
    }

    @Test("Clearing, as a send or link landing does, leaves nothing to return to")
    func clear_emptiesStack() async {
        let (controller, window) = await host()
        tapQuote(controller, quoted: 3, in: 20)
        controller.clearReplyReturns()
        #expect(controller.replyReturns.isEmpty)
        _ = window
    }

    @Test("A row is reached once its top edge is above the visible area's bottom")
    func isReached_geometry() {
        let visible = CGRect(x: 0, y: 1000, width: 390, height: 700)
        // On screen.
        #expect(ChatViewController.isReached(CGRect(x: 0, y: 1200, width: 390, height: 60), in: visible))
        // Scrolled above the top.
        #expect(ChatViewController.isReached(CGRect(x: 0, y: 500, width: 390, height: 60), in: visible))
        // Peeking in at the bottom edge.
        #expect(ChatViewController.isReached(CGRect(x: 0, y: 1690, width: 390, height: 60), in: visible))
        // Still below the screen.
        #expect(!ChatViewController.isReached(CGRect(x: 0, y: 1700, width: 390, height: 60), in: visible))
    }
}
