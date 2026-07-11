//
//  Regression_6a522ee9fdca5cb0d6f21174.swift
//  FlipcashTests
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// A push that inserts rows above a reconfigured row resolved the reconfigure against the target
/// array at its source-coordinate index path — another row's element: the wrong bubble on a
/// same-class row, an `NSInternalInconsistencyException` on a cross-class one ("Dequeued reuse
/// identifier: ChatCashCardCell; Original reuse identifier: ChatMessageCell"). The tests must
/// stay window-attached (off-window `reload` skips the diff path) and read live cells (the
/// data-source method re-dequeues and cannot see a misconfigured cell); serialized because a
/// regression here aborts the runner.
@MainActor
@Suite("Regression: 6a522ee – reconfigure resolves against shifted indices", .serialized, .bug("6a522ee9fdca5cb0d6f21174"))
struct Regression_6a522ee9fdca5cb0d6f21174 {

    /// The window keeps the controller's view attached for the test's lifetime; dropping it would
    /// silently reroute `update` onto the off-window `reloadData` path.
    private struct WindowedTranscript {
        let window: UIWindow
        let controller: ChatViewController
    }

    private func windowedTranscript(seed: [ChatItem]) async -> WindowedTranscript {
        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: seed)
        await settle(controller)
        return WindowedTranscript(window: window, controller: controller)
    }

    private func settle(_ controller: ChatViewController) async {
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func bubbleText(in controller: ChatViewController, item: Int) -> String? {
        guard let cell = controller.collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? ChatMessageCell else {
            return nil
        }
        return firstLabel(in: cell.bubbleView)?.text
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        for subview in view.subviews {
            if let label = subview as? UILabel { return label }
            if let nested = firstLabel(in: subview) { return nested }
        }
        return nil
    }

    @Test("An insert above a reconfigured row keeps every bubble on its own row")
    func update_insertAboveReconfiguredRow_rendersEachRowsOwnText() async {
        let transcript = await windowedTranscript(seed: [
            .message(ChatMessage(id: "a", text: "alpha", sender: .me)),
            .message(ChatMessage(id: "b", text: "bravo", sender: .me)),
        ])

        // "n" is new (insert at target 0); "a" changes content only (an update at source 0).
        transcript.controller.update(items: [
            .message(ChatMessage(id: "n", text: "newest", sender: .other)),
            .message(ChatMessage(id: "a", text: "alpha", sender: .me, receipt: "Read")),
            .message(ChatMessage(id: "b", text: "bravo", sender: .me)),
        ])
        await settle(transcript.controller)

        #expect(bubbleText(in: transcript.controller, item: 0) == "newest")
        #expect(bubbleText(in: transcript.controller, item: 1) == "alpha")
        #expect(bubbleText(in: transcript.controller, item: 2) == "bravo")
    }

    @Test("A cash card inserted above a reconfigured text row does not dequeue across classes")
    func update_cashInsertAboveReconfiguredRow_doesNotCrash() async {
        let transcript = await windowedTranscript(seed: [
            .message(ChatMessage(id: "a", text: "alpha", sender: .me)),
            .message(ChatMessage(id: "b", text: "bravo", sender: .me)),
        ])

        transcript.controller.update(items: [
            .message(ChatMessage(id: "n", content: .cash(ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: "us")), sender: .other)),
            .message(ChatMessage(id: "a", text: "alpha", sender: .me, receipt: "Read")),
            .message(ChatMessage(id: "b", text: "bravo", sender: .me)),
        ])
        await settle(transcript.controller)

        #expect(transcript.controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) is ChatCashCardCell)
        #expect(bubbleText(in: transcript.controller, item: 1) == "alpha")
        #expect(bubbleText(in: transcript.controller, item: 2) == "bravo")
    }
}
