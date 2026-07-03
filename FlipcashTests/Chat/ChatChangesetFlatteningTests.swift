//
//  ChatChangesetFlatteningTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import DifferenceKit
import FlipcashCore
@testable import FlipcashUI

/// `StagedChangeset.flattenIfPossible` must merge DifferenceKit's staged changesets into a single
/// changeset whenever no moves are involved, so the transcript applies one `performBatchUpdates`
/// with one keep-at-bottom compensation. Split stages run as overlapping animated batch updates,
/// which is what made cells slide in from random directions when a receipt or grouping change
/// landed together with an insert.
@MainActor
@Suite("Chat changeset flattening")
struct ChatChangesetFlatteningTests {

    private func message(
        _ id: String,
        sender: ChatMessage.Sender = .me,
        continuedByNext: Bool = false,
        continuationFromPrevious: Bool = false,
        receipt: String? = nil
    ) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: "text-\(id)",
            sender: sender,
            isContinuationFromPrevious: continuationFromPrevious,
            isContinuedByNext: continuedByNext,
            receipt: receipt
        ))
    }

    @Test("A send (previous-row update + insert) flattens to a single changeset")
    func updateAndInsert_flattensToOne() {
        // A new own message migrates the receipt off the previous row and flips its grouping —
        // an update — while the new row is an insert. DifferenceKit stages these separately.
        let before = [message("a", receipt: "Delivered")]
        let after = [
            message("a", continuedByNext: true),
            message("b", continuationFromPrevious: true, receipt: "Delivered"),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 2, "premise: DifferenceKit stages [updates]+[inserts] separately")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == 1)
        guard let merged = flattened.first else { return }
        #expect(merged.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementDeleted.isEmpty)
        #expect(merged.elementMoved.isEmpty)
        #expect(merged.data == after)
    }

    @Test("An arrival while typing (update + delete + insert) flattens to a single changeset")
    func updateDeleteAndInsert_flattensToOne() {
        // The typing indicator clears (delete), the reply lands (insert), and the previous row's
        // grouping flips (update) — three DifferenceKit stages in one push.
        let before = [message("a", sender: .other), .typingIndicator]
        let after = [
            message("a", sender: .other, continuedByNext: true),
            message("b", sender: .other, continuationFromPrevious: true),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 3, "premise: DifferenceKit stages [updates]+[deletes]+[inserts] separately")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == 1)
        guard let merged = flattened.first else { return }
        #expect(merged.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(merged.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementMoved.isEmpty)
        #expect(merged.data == after)
    }

    @Test("A pure delete + insert pair still flattens to a single changeset")
    func deleteAndInsert_stillFlattensToOne() {
        // The pre-existing behavior (typing indicator swaps for a message with no other change).
        let before = [message("a", sender: .other), .typingIndicator]
        let after = [message("a", sender: .other), message("b", sender: .other)]

        let flattened = StagedChangeset(source: before, target: after).flattenIfPossible()
        #expect(flattened.count == 1)
        guard let merged = flattened.first else { return }
        #expect(merged.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.data == after)
    }

    @Test("Stages containing moves are left un-flattened")
    func moves_areNotFlattened() {
        // A move's source index is relative to the post-delete stage, not the original source, so
        // merging would corrupt indices. Reorders never happen in a transcript; keep them staged.
        let before = [message("a"), message("b")]
        let after = [message("b"), .message(ChatMessage(id: "a", text: "edited", sender: .me))]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.contains { !$0.elementMoved.isEmpty }, "premise: a reorder diffs to a move")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == staged.count)
        #expect(flattened.contains { !$0.elementMoved.isEmpty })
    }
}
