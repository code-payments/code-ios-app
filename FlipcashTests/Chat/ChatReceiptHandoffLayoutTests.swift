//
//  ChatReceiptHandoffLayoutTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// The receipt handoff, watched frame by frame on a live transcript. The row giving up "Delivered"
/// shrinks by the line as the row below grows by it, so the row above must hold perfectly still
/// while the one below glides up into the gap, and the line it gave up must be gone before that
/// row arrives over it.
@MainActor
@Suite("Chat receipt handoff layout", .timingSensitive)
struct ChatReceiptHandoffLayoutTests {

    /// One frame of the handoff, read off the presentation tree.
    private struct Frame {
        /// The top of the row above's bubble.
        let aTop: CGFloat
        /// The top of the row below's bubble.
        let bTop: CGFloat
        /// The bottom of the line the row above gave up, and its opacity, while it is still fading.
        let fadingLine: (bottom: CGFloat, opacity: CGFloat)?
        /// The horizontal scale the row below's new line is drawn at.
        let newLineScale: CGFloat?
    }

    private struct Handoff {
        /// The frame before the handoff started.
        let rest: Frame
        /// A frame at a time across the reflow spring.
        let frames: [Frame]
    }

    private func filler(_ i: Int) -> ChatItem {
        .message(ChatMessage(id: "msg-\(i)", text: "message \(i)", sender: i.isMultiple(of: 2) ? .me : .other))
    }

    /// Two own sends in one bubble run, the second still waiting for its receipt: a real send's shape.
    private func run(receiptOnSecond: Bool) -> [ChatItem] {
        (0..<10).map(filler) + [
            .message(ChatMessage(
                id: "a", text: "The first time we were", sender: .me,
                isContinuedByNext: true, joinsBubbleBelow: true,
                receipt: receiptOnSecond ? nil : .delivered
            )),
            .message(ChatMessage(
                id: "b", text: "The only way I", sender: .me,
                isContinuationFromPrevious: true, joinsBubbleAbove: true,
                receipt: receiptOnSecond ? .delivered : nil
            )),
        ]
    }

    private func shown(_ view: UIView, in window: UIWindow) -> (frame: CGRect, opacity: CGFloat)? {
        guard let layer = view.layer.presentation(), let windowLayer = window.layer.presentation() else { return nil }
        return (layer.convert(layer.bounds, to: windowLayer), CGFloat(layer.opacity))
    }

    private func frame(of controller: ChatViewController, in window: UIWindow) throws -> Frame {
        func cell(_ item: Int) throws -> ChatMessageCell {
            try #require(controller.collectionView.cellForItem(at: IndexPath(item: item, section: 0)) as? ChatMessageCell)
        }
        let a = try cell(10)
        let b = try cell(11)
        let line = try #require(Self.receipt(in: a)).fadingLine.flatMap { shown($0, in: window) }
        let newLine = try #require(Self.receipt(in: b)).currentFace.layer.presentation()
        return Frame(
            aTop: try #require(shown(a.bubbleView, in: window)).frame.minY,
            bTop: try #require(shown(b.bubbleView, in: window)).frame.minY,
            fadingLine: line.map { ($0.frame.maxY, $0.opacity) },
            newLineScale: newLine.map { $0.affineTransform().a }
        )
    }

    private static func receipt(in view: UIView) -> ChatReceiptView? {
        if let receipt = view as? ChatReceiptView { return receipt }
        return view.subviews.lazy.compactMap(receipt(in:)).first
    }

    /// Plays the handoff in a rendering window and records it.
    private func playHandoff() async throws -> Handoff {
        let controller = ChatViewController()
        // Attached to the host's scene so the window renders: a detached window has no presentation
        // layers, and both glitches live only there.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        controller.update(items: run(receiptOnSecond: false))
        for _ in 0..<8 {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        let rest = try frame(of: controller, in: window)

        controller.update(items: run(receiptOnSecond: true))
        var frames: [Frame] = []
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(16))
            frames.append(try frame(of: controller, in: window))
        }
        return Handoff(rest: rest, frames: frames)
    }

    @Test("The row giving up its receipt never moves while the next row takes it")
    func handoff_rowAboveHoldsStill() async throws {
        let handoff = try await playHandoff()

        let drift = handoff.frames.map { abs($0.aTop - handoff.rest.aTop) }.max() ?? 0
        #expect(drift < 0.5, "The row above moved \(drift) pt during the handoff")
        let bEnd = try #require(handoff.frames.last).bTop
        #expect(bEnd < handoff.rest.bTop - 10, "The row below should glide up into the gap the line left")
    }

    @Test("The line the row above gives up is gone before the row below reaches it")
    func handoff_oldLineGoneBeforeRowBelowArrives() async throws {
        let handoff = try await playHandoff()

        // The first frame the row below's top edge is over the fading line, if the line is still
        // there by then. None at all means the line had already gone.
        let overlap = handoff.frames.first { frame in
            frame.fadingLine.map { frame.bTop < $0.bottom } ?? false
        }
        let opacity = overlap?.fadingLine?.opacity ?? 0
        #expect(opacity < 0.15, "The old line was still at \(opacity) opacity when the row below reached it")
    }

    @Test("The row below's new line grows in from its start scale while the transcript reflows")
    func handoff_newLineGrowsIn() async throws {
        let handoff = try await playHandoff()

        // Its start state is set inside the batch update's animation block; assigned there, it
        // would be animated to rather than started from, and the line would never visibly scale.
        let first = try #require(handoff.frames.first?.newLineScale)
        #expect(first < 0.99, "The new line was drawn at \(first) scale on the handoff's first frame")
        let last = try #require(handoff.frames.last?.newLineScale)
        #expect(abs(last - 1) < 0.01)
    }
}
