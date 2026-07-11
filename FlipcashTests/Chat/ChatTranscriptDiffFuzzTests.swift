//
//  ChatTranscriptDiffFuzzTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import UIKit
import FlipcashCore
@testable import FlipcashUI

/// Property test for the transcript's diff→apply pipeline: after any sequence of pushes, every
/// visible cell must render its own row — class and content both matching `items` — and no push
/// may throw. Transitions come from a seeded PRNG so any failure replays exactly, biased toward
/// structural changes above updated rows, cell-class flips at a stable id, and reorders (the
/// staged path); serialized because a found bug can abort the runner, and one case at a time
/// keeps the failing seed unambiguous.
@MainActor
@Suite("Chat transcript diff fuzz", .serialized)
struct ChatTranscriptDiffFuzzTests {

    /// Deterministic SplitMix64 so every run of a seed produces the identical push sequence.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Compact per-row spec the generator mutates; content strings derive from ids so the
    /// readback asserts know what each row must say.
    private enum Row {
        case text(id: Int, receipt: Bool, grouped: Bool)
        case link(id: Int)
        case cash(id: Int)
        case separator(id: Int)
        case typing

        var messageID: Int? {
            switch self {
            case .text(let id, _, _), .link(let id), .cash(let id), .separator(let id): id
            case .typing: nil
            }
        }
    }

    private func build(_ rows: [Row]) -> [ChatItem] {
        rows.map { row in
            switch row {
            case .text(let id, let receipt, let grouped):
                .message(ChatMessage(
                    id: "m\(id)",
                    text: "text-\(id)",
                    sender: id.isMultiple(of: 2) ? .me : .other,
                    isContinuationFromPrevious: grouped,
                    receipt: receipt ? "Read" : nil
                ))
            case .link(let id):
                .message(ChatMessage(
                    id: "m\(id)",
                    text: "link-\(id) https://example.com",
                    sender: .me,
                    linkPreview: LinkPreview(url: URL(string: "https://example.com/\(id)")!)
                ))
            case .cash(let id):
                .message(ChatMessage(
                    id: "m\(id)",
                    content: .cash(ChatCashContent(amount: "$\(id).00", token: "Cash", flagImageName: "us")),
                    sender: .other
                ))
            case .separator(let id):
                .dateSeparator(id: "sep\(id)", text: "Day \(id)")
            case .typing:
                .typingIndicator
            }
        }
    }

    /// One random mutation, weighted toward structural changes at the top of the transcript so
    /// they land above updated rows.
    private func mutate(_ rows: inout [Row], nextID: inout Int, using rng: inout SplitMix64) {
        switch Int.random(in: 0..<10, using: &rng) {
        case 0, 1: // prepend a new row (message or separator)
            let id = nextID
            nextID += 1
            let row: Row = Bool.random(using: &rng) ? .cash(id: id) : (Bool.random(using: &rng) ? .text(id: id, receipt: false, grouped: false) : .separator(id: id))
            rows.insert(row, at: 0)
        case 2: // append a new message
            let id = nextID
            nextID += 1
            rows.append(.text(id: id, receipt: false, grouped: false))
        case 3: // remove a random row
            if !rows.isEmpty { rows.remove(at: Int.random(in: 0..<rows.count, using: &rng)) }
        case 4, 5: // content-mutate a text row (receipt/grouping toggle)
            let textIndices = rows.indices.filter { if case .text = rows[$0] { true } else { false } }
            if let index = textIndices.randomElement(using: &rng),
               case .text(let id, let receipt, let grouped) = rows[index] {
                rows[index] = Bool.random(using: &rng)
                    ? .text(id: id, receipt: !receipt, grouped: grouped)
                    : .text(id: id, receipt: receipt, grouped: !grouped)
            }
        case 6, 7: // kind-flip at a stable id (text ↔ cash ↔ link)
            let messageIndices = rows.indices.filter { rows[$0].messageID != nil }
            if let index = messageIndices.randomElement(using: &rng), let id = rows[index].messageID {
                switch rows[index] {
                case .text: rows[index] = Bool.random(using: &rng) ? .cash(id: id) : .link(id: id)
                case .cash, .link: rows[index] = .text(id: id, receipt: false, grouped: false)
                case .separator, .typing: break
                }
            }
        case 8: // reorder (swap) — diffs to moves
            if rows.count >= 2 {
                let a = Int.random(in: 0..<rows.count, using: &rng)
                let b = Int.random(in: 0..<rows.count, using: &rng)
                rows.swapAt(a, b)
            }
        default: // toggle the typing indicator
            if let index = rows.firstIndex(where: { if case .typing = $0 { true } else { false } }) {
                rows.remove(at: index)
            } else {
                rows.append(.typing)
            }
        }
    }

    private func firstLabel(in view: UIView) -> UILabel? {
        for subview in view.subviews {
            if let label = subview as? UILabel { return label }
            if let nested = firstLabel(in: subview) { return nested }
        }
        return nil
    }

    /// Asserts every visible cell is the class its item dequeues by and every text bubble shows
    /// its own row's text.
    private func assertConsistent(_ controller: ChatViewController, items: [ChatItem], seed: UInt64, push: Int) {
        let collectionView = controller.collectionView!
        #expect(collectionView.numberOfItems(inSection: 0) == items.count, "row count diverged — seed \(seed) push \(push)")
        for (index, item) in items.enumerated() {
            guard let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) else { continue }
            #expect(String(describing: type(of: cell)) == item.cellReuseIdentifier,
                    "class mismatch at row \(index) — seed \(seed) push \(push)")
            if case .message(let message) = item, case .text(let text) = message.content,
               let messageCell = cell as? ChatMessageCell {
                #expect(firstLabel(in: messageCell.bubbleView)?.text == text,
                        "content mismatch at row \(index) — seed \(seed) push \(push)")
            }
        }
    }

    @Test("Randomized push sequences keep every visible cell on its own row", arguments: [
        UInt64(0x6A52_2EE9), UInt64(0x6A4F_895B), UInt64(0xDEAD_BEEF), UInt64(0x0BAD_F00D),
    ])
    func randomizedPushes_keepTranscriptConsistent(seed: UInt64) async {
        var rng = SplitMix64(state: seed)
        var nextID = 0
        var rows: [Row] = (0..<6).map { _ in
            defer { nextID += 1 }
            return .text(id: nextID, receipt: false, grouped: false)
        }

        let controller = ChatViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.update(items: build(rows))
        for _ in 0..<3 {
            controller.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }

        for push in 0..<40 {
            // The size clamp keeps every row on screen, so the live-cell asserts see the whole
            // transcript.
            for _ in 0..<Int.random(in: 1...3, using: &rng) {
                if rows.count > 14 {
                    rows.remove(at: Int.random(in: 0..<rows.count, using: &rng))
                } else if rows.count < 3 {
                    rows.append(.text(id: nextID, receipt: false, grouped: false))
                    nextID += 1
                } else {
                    mutate(&rows, nextID: &nextID, using: &rng)
                }
            }
            let items = build(rows)
            controller.update(items: items)
            controller.view.layoutIfNeeded()
            assertConsistent(controller, items: items, seed: seed, push: push)
        }
    }
}
