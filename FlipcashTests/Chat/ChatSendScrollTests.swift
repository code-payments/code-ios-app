//
//  ChatSendScrollTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// A send's scroll and the bar's inset, watched frame by frame on a live transcript.
@MainActor
@Suite("Chat send scroll", .timingSensitive)
struct ChatSendScrollTests {

    private func filler(_ i: Int) -> ChatItem {
        .message(ChatMessage(id: "msg-\(i)", text: "message \(i)", sender: i.isMultiple(of: 2) ? .me : .other))
    }

    private let sent = ChatItem.message(ChatMessage(id: "sent", text: "Sent just now", sender: .me))

    /// A transcript in a rendering window, settled at its newest message above a bar of `inset`.
    private func host(inset: CGFloat) async throws -> (ChatViewController, UIWindow) {
        let controller = ChatViewController()
        // Attached to the host's scene so the window renders: a detached window has no presentation
        // layers, and the motion lives only there.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: (0..<30).map(filler))
        controller.setBottomInset(inset)
        for _ in 0..<8 {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        return (controller, window)
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    /// The bottom of the newest row as drawn, in window coordinates.
    private func lastBottom(_ controller: ChatViewController, in window: UIWindow) -> CGFloat? {
        let count = controller.collectionView.numberOfItems(inSection: 0)
        guard let cell = controller.collectionView.cellForItem(at: IndexPath(item: count - 1, section: 0)),
              let layer = cell.layer.presentation(), let windowLayer = window.layer.presentation() else { return nil }
        return layer.convert(layer.bounds, to: windowLayer).maxY
    }

    private func sample(_ frames: Int, _ read: () -> CGFloat?) async throws -> [CGFloat] {
        var samples: [CGFloat] = []
        for _ in 0..<frames {
            try await Task.sleep(for: .milliseconds(16))
            if let value = read() { samples.append(value) }
        }
        return samples
    }

    @Test("At rest at the bottom the transcript reports it; scrolled up it doesn't")
    func isAtBottomTracksPosition() async throws {
        let (controller, window) = try await host(inset: 80)
        defer { close(window) }
        #expect(controller.isAtBottom)
        controller.collectionView.setContentOffset(CGPoint(x: 0, y: controller.collectionView.contentOffset.y - 300), animated: false)
        #expect(!controller.isAtBottom)
    }

    @Test("An own send at the bottom lands at the bottom on its own, with no second scroll")
    func sendAtBottomFollowsItself() async throws {
        let (controller, window) = try await host(inset: 80)
        defer { close(window) }
        let rest = try #require(lastBottom(controller, in: window))
        controller.update(items: (0..<30).map(filler) + [sent])
        let samples = try await sample(40) { lastBottom(controller, in: window) }
        let landed = try #require(samples.last)
        #expect(abs(landed - rest) < 1, "The new row landed at \(landed), the bottom row sat at \(rest)")
        #expect(controller.isAtBottom)
    }

    @Test("An own send while scrolled up in history still brings the transcript to the bottom")
    func sendScrolledUpReachesBottom() async throws {
        let (controller, window) = try await host(inset: 80)
        defer { close(window) }
        controller.collectionView.setContentOffset(CGPoint(x: 0, y: controller.collectionView.contentOffset.y - 400), animated: false)
        #expect(!controller.isAtBottom)
        controller.update(items: (0..<30).map(filler) + [sent])
        controller.scrollToBottom(animated: true)
        _ = try await sample(50) { nil }
        #expect(controller.isAtBottom)
    }

    @Test("A bar shrinking mid-send carries the transcript down with it, gliding and without a late snap")
    func barShrinkMidInsertFollows() async throws {
        let (controller, window) = try await host(inset: 120)
        defer { close(window) }
        controller.update(items: (0..<30).map(filler) + [sent])
        try await Task.sleep(for: .milliseconds(16))
        // A multiline draft collapsing to one line as the send lands: the bar is 40 pt shorter.
        controller.setBottomInset(80)
        let samples = try await sample(50) { lastBottom(controller, in: window) }

        // Where the newest row rests above the 80 pt bar.
        let rest = try #require(samples.last)
        let (settled, settledWindow) = try await host(inset: 80)
        defer { close(settledWindow) }
        let expected = try #require(lastBottom(settled, in: settledWindow))
        #expect(abs(rest - expected) < 1, "Rested at \(rest), a transcript over the shorter bar rests at \(expected)")

        // Within about half a second of the bar moving, not at the insert's completion.
        let caughtUp = samples.firstIndex { abs($0 - rest) < 1 } ?? samples.count
        #expect(caughtUp < 30, "Took \(caughtUp) frames to reach the new bar")
        let jump = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        #expect(jump < 15, "The newest row jumped \(jump) pt in one frame")
        // The row rises in from below its slot as any append does; once it has reached its place it
        // never sinks back under the bar.
        let arrived = samples.firstIndex { $0 <= rest + 0.5 } ?? samples.count
        let sink = samples[arrived...].map { $0 - rest }.max() ?? 0
        #expect(sink < 1.5, "The newest row sank \(sink) pt past its resting place, under the bar")
    }
}
