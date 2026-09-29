//
//  ChatTypingHandoffTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// One row of the shared case table in `docs/cross-platform-parity.md` (flipcash-client-orchestrator,
/// "Shared rule: typing-dots handoff with several typists"). Android encodes the same eight rows.
struct TypingHandoffCase: CustomTestStringConvertible, Sendable {

    /// What the dots row does in the update.
    enum DotsAfter: Sendable {
        /// Handed to the arrival that takes its frame.
        case gone
        /// There were no dots before the update either.
        case notShown
        /// Survives as the newest row, showing these typists.
        case stays([String])
        /// Leaves on its normal exit; nobody takes its frame.
        case exits
    }

    let name: String
    /// A DM: its dots and incoming rows carry no author.
    let isDM: Bool
    let typingBefore: [String]
    /// Senders, oldest first; `self` is the viewer.
    let arrivals: [String]
    let takesFrame: String?
    let dotsAfter: DotsAfter

    var testDescription: String { name }

    var typingAfter: [String] {
        switch dotsAfter {
        case .gone, .notShown, .exits: []
        case .stays(let typists): typists
        }
    }

    static let viewer = "self"

    static let table: [TypingHandoffCase] = [
        .init(name: "DM reply", isDM: true, typingBefore: ["A"], arrivals: ["A"], takesFrame: "A", dotsAfter: .gone),
        // Lingering after STOPPED keeps A in the typist set, so it reads the same as the row above.
        .init(name: "DM reply during linger", isDM: true, typingBefore: ["A"], arrivals: ["A"], takesFrame: "A", dotsAfter: .gone),
        .init(name: "Linger already expired", isDM: true, typingBefore: [], arrivals: ["A"], takesFrame: nil, dotsAfter: .notShown),
        .init(name: "Group, one of two sends", isDM: false, typingBefore: ["A", "B"], arrivals: ["A"], takesFrame: nil, dotsAfter: .stays(["B"])),
        .init(name: "Group, non-typist sends", isDM: false, typingBefore: ["A"], arrivals: ["B"], takesFrame: nil, dotsAfter: .stays(["A"])),
        .init(name: "Viewer sends", isDM: false, typingBefore: ["A"], arrivals: [viewer], takesFrame: nil, dotsAfter: .stays(["A"])),
        .init(name: "Group, both send together", isDM: false, typingBefore: ["A", "B"], arrivals: ["A", "B"], takesFrame: "B", dotsAfter: .gone),
        .init(name: "Newest arrival wasn't typing", isDM: false, typingBefore: ["A"], arrivals: ["A", "B"], takesFrame: nil, dotsAfter: .exits),
    ]
}

@Suite("Typing dots handoff rule")
struct TypingDotsHandoffRuleTests {

    @Test("The shared case table", arguments: TypingHandoffCase.table)
    func sharedCase(_ c: TypingHandoffCase) {
        let taker = TypingDotsHandoff.takerIndex(
            typingBefore: Set(c.typingBefore),
            arrivals: c.arrivals,
            typingAfter: Set(c.typingAfter)
        )
        #expect(taker.map { c.arrivals[$0] } == c.takesFrame)
    }
}

@MainActor
@Suite("Typing handoff detection")
struct ChatTypingHandoffDetectionTests {

    private static let authors = Dictionary(uniqueKeysWithValues: ["A", "B"].map { ($0, ChatAuthor(id: UserID(), name: $0)) })

    private func row(_ id: String, _ sender: ChatMessage.Sender = .other, author: String? = nil, part: ChatMessagePart.Kind? = nil) -> ChatItem {
        .message(ChatMessage(
            id: id, text: id, sender: sender,
            author: author.flatMap { Self.authors[$0] }, isAttributedTranscript: author != nil,
            part: part.map { ChatMessagePart(messageID: "split", kind: $0, messageText: id) }
        ))
    }

    private let dots = ChatItem.typingIndicator(typists: [])

    private func dots(_ typists: [String], dm: Bool) -> ChatItem {
        .typingIndicator(typists: dm ? [] : typists.compactMap { Self.authors[$0] })
    }

    /// The case as the transcript hands it over: one earlier row, the dots trailing it while anyone
    /// types, and the arrivals appended above wherever the dots still are.
    @Test("The shared case table, as transcript updates", arguments: TypingHandoffCase.table)
    func sharedCase(_ c: TypingHandoffCase) {
        let base = row("base", .me)
        let old = [base] + (c.typingBefore.isEmpty ? [] : [dots(c.typingBefore, dm: c.isDM)])
        let arrivals = c.arrivals.enumerated().map { index, sender in
            sender == TypingHandoffCase.viewer
                ? row("m\(index)", .me, author: nil)
                : row("m\(index)", author: c.isDM ? nil : sender)
        }
        let new = [base] + arrivals + (c.typingAfter.isEmpty ? [] : [dots(c.typingAfter, dm: c.isDM)])
        let expected = c.takesFrame.flatMap { taker in c.arrivals.lastIndex(of: taker) }.map { 1 + $0 }
        #expect(ChatViewController.typingHandoffRow(from: old, to: new) == expected)
    }

    @Test("An own message, the dots leaving alone, or no dots to hand over are not a handoff")
    func notAHandoff() {
        #expect(ChatViewController.typingHandoffRow(from: [row("a"), dots], to: [row("a"), row("b", .me)]) == nil)
        #expect(ChatViewController.typingHandoffRow(from: [row("a"), dots], to: [row("a")]) == nil)
        #expect(ChatViewController.typingHandoffRow(from: [row("a")], to: [row("a"), row("b")]) == nil)
    }

    @Test("A non-typist's message landing as the last typist's dots leave inserts normally")
    func nonTypistAsDotsLeave() {
        let old = [row("a"), dots(["A"], dm: false)]
        #expect(ChatViewController.typingHandoffRow(from: old, to: [row("a"), row("b", author: "B")]) == nil)
    }

    @Test("A date heading arriving ahead of the reply does not stop the handoff")
    func headingAhead() {
        let heading = ChatItem.dateSeparator(id: "day", text: "Today")
        #expect(ChatViewController.typingHandoffRow(from: [row("a"), dots], to: [row("a"), heading, row("b")]) == 2)
    }

    @Test("A reply split around its link card inserts normally")
    func splitReplyFallsBack() {
        let new = [row("a"), row("b.text", part: .leadingText), row("b.card", part: .card)]
        #expect(ChatViewController.typingHandoffRow(from: [row("a"), dots], to: new) == nil)
    }
}

/// The typing bubble growing into the message that replaces it, watched frame by frame on a live
/// transcript: the chrome starts on the dots bubble and grows to the message's, the thread above
/// makes room without the bubble ever running into it, the text arrives by opacity alone, and in a
/// group the author's face travels over from the dots' stack.
@MainActor
@Suite("Typing handoff layout")
struct ChatTypingHandoffLayoutTests {

    private static let author = ChatAuthor(id: UserID(), name: "Sam")

    /// One frame of the handoff, in window coordinates, read off the presentation tree.
    private struct Frame {
        /// The outline the arriving bubble's chrome is drawn inside.
        let chrome: CGRect
        /// The bottom of the row above's bubble.
        let aboveBottom: CGFloat
        /// The arriving text's opacity.
        let textOpacity: CGFloat
        /// The dots' copy's opacity, while it is still there.
        let dotsOpacity: CGFloat?
        /// The arriving row's gutter face.
        let face: CGRect?
    }

    private struct Handoff {
        /// The dots bubble, just before the message arrived.
        let dots: CGRect
        /// The dots' stack face, just before the message arrived.
        let dotsFace: CGRect?
        /// The arriving bubble's own frame once it has landed.
        let landed: CGRect
        let frames: [Frame]
    }

    private func filler(_ i: Int, group: Bool) -> ChatItem {
        let sender: ChatMessage.Sender = i.isMultiple(of: 2) ? .me : .other
        return .message(ChatMessage(
            id: "msg-\(i)", text: "message \(i)", sender: sender,
            author: group && sender == .other ? ChatAuthor(id: UserID(), name: "Other \(i)") : nil,
            isAttributedTranscript: group
        ))
    }

    private func reply(group: Bool) -> ChatItem {
        .message(ChatMessage(
            id: "reply", text: "Got it, see you at noon then, I'll bring the thing", sender: .other,
            author: group ? Self.author : nil, isAttributedTranscript: group
        ))
    }

    private func shown(_ layer: CALayer?, _ rect: CGRect? = nil, in window: UIWindow) -> CGRect? {
        guard let layer = layer?.presentation(), let windowLayer = window.layer.presentation() else { return nil }
        return layer.convert(rect ?? layer.bounds, to: windowLayer)
    }

    private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private func play(rows: Int, group: Bool) async throws -> Handoff {
        let controller = ChatViewController()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let base = (0..<rows).map { filler($0, group: group) }
        let typists = group ? [Self.author] : []
        controller.update(items: base + [.typingIndicator(typists: typists)])
        for _ in 0..<8 {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        let typing = try #require(controller.collectionView.cellForItem(at: IndexPath(item: rows, section: 0)))
        let dotsBubble = try #require(Self.find(BubbleBackgroundView.self, in: typing))
        let dots = try #require(shown(dotsBubble.layer, in: window))
        let dotsFace = Self.find(ChatAuthorAvatarView.self, in: typing).flatMap { shown($0.layer, in: window) }

        controller.update(items: base + [reply(group: group)])
        // Commits the update, so the arriving row has a presentation layer to read at its start.
        CATransaction.flush()
        let cell = try #require(controller.collectionView.cellForItem(at: IndexPath(item: rows, section: 0)) as? ChatMessageCell)
        let chrome = try #require(Self.find(BubbleBackgroundView.self, in: cell.bubbleView))
        let text = try #require(Self.find(UILabel.self, in: cell.bubbleView))
        let above = try #require(controller.collectionView.cellForItem(at: IndexPath(item: rows - 1, section: 0)) as? ChatMessageCell)

        func sample() throws -> Frame {
            let outline = try #require(chrome.presentedOutline)
            return Frame(
                chrome: try #require(shown(chrome.layer, outline, in: window)),
                aboveBottom: try #require(shown(above.bubbleView.layer, in: window)).maxY,
                textOpacity: CGFloat(text.layer.presentation()?.opacity ?? text.layer.opacity),
                dotsOpacity: cell.fadingTypingRemnants.first.map { CGFloat($0.layer.presentation()?.opacity ?? 0) },
                face: cell.authorFace.isHidden ? nil : shown(cell.authorFace.layer, in: window)
            )
        }

        var frames = [try sample()]
        for _ in 0..<45 {
            try await Task.sleep(for: .milliseconds(16))
            frames.append(try sample())
        }
        return Handoff(dots: dots, dotsFace: dotsFace, landed: try #require(shown(chrome.layer, in: window)), frames: frames)
    }

    private func near(_ a: CGRect, _ b: CGRect, within tolerance: CGFloat = 1.5) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    @Test("The bubble starts on the dots bubble and grows to its own", arguments: [false, true])
    func growsFromDots(group: Bool) async throws {
        let handoff = try await play(rows: 30, group: group)
        let first = try #require(handoff.frames.first)
        #expect(near(first.chrome, handoff.dots), "Started at \(first.chrome), the dots were at \(handoff.dots)")
        let last = try #require(handoff.frames.last)
        #expect(near(last.chrome, handoff.landed), "Ended at \(last.chrome), the bubble is at \(handoff.landed)")
        // Anchored where the dots sat: a thread longer than the screen keeps its bottom pinned, so
        // the bubble grows up and out from the dots' bottom edge.
        let drift = handoff.frames.map { abs($0.chrome.maxY - handoff.dots.maxY) }.max() ?? 0
        #expect(drift < 1.5, "The bubble's bottom edge moved \(drift) pt")
    }

    @Test("The row above makes room and the growing bubble never runs into it", arguments: [false, true])
    func pushesThreadWithoutOverlap(group: Bool) async throws {
        let handoff = try await play(rows: 30, group: group)
        let overlap = handoff.frames.map { $0.aboveBottom - $0.chrome.minY }.max() ?? 0
        #expect(overlap < 0.5, "The row above overlapped the arriving bubble by \(overlap) pt")
        let start = try #require(handoff.frames.first).aboveBottom
        let end = try #require(handoff.frames.last).aboveBottom
        #expect(end < start - 5, "The row above should have been pushed up to make room")
    }

    @Test("The text fades in rather than arriving at full strength, and the dots fade out")
    func textFadesInDotsFadeOut() async throws {
        let handoff = try await play(rows: 30, group: false)
        let first = try #require(handoff.frames.first)
        #expect(first.textOpacity < 0.05)
        #expect(try #require(handoff.frames.last).textOpacity > 0.99)
        let dots = try #require(first.dotsOpacity)
        #expect(dots > 0.9, "The dots should start at full strength, were \(dots)")
        #expect(handoff.frames.last?.dotsOpacity == nil, "The dots' copy should be gone once it has faded")
    }

    @Test("In a group the author's face travels over from the dots' stack")
    func faceTravelsFromStack() async throws {
        let handoff = try await play(rows: 30, group: true)
        let dotsFace = try #require(handoff.dotsFace)
        let first = try #require(handoff.frames.first?.face)
        #expect(abs(first.midX - dotsFace.midX) < 1.5 && abs(first.midY - dotsFace.midY) < 1.5,
                "The face started at \(first), the stack's was at \(dotsFace)")
        // Every frame between is on the way, never a jump.
        let steps = zip(handoff.frames, handoff.frames.dropFirst()).compactMap { pair -> CGFloat? in
            guard let a = pair.0.face, let b = pair.1.face else { return nil }
            return hypot(b.midX - a.midX, b.midY - a.midY)
        }
        #expect((steps.max() ?? 0) < 12, "The face jumped \(steps.max() ?? 0) pt in one frame")
    }

    @Test("A short thread keeps the bubble on the dots' top edge as it grows down")
    func shortThreadGrowsDown() async throws {
        let handoff = try await play(rows: 3, group: false)
        let first = try #require(handoff.frames.first)
        #expect(near(first.chrome, handoff.dots), "Started at \(first.chrome), the dots were at \(handoff.dots)")
        let overlap = handoff.frames.map { $0.aboveBottom - $0.chrome.minY }.max() ?? 0
        #expect(overlap < 0.5)
    }
}
