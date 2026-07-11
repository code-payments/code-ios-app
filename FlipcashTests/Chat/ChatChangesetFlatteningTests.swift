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

/// `StagedChangeset.singleBatch` must express a no-moves diff as one `performBatchUpdates` (split
/// stages run as overlapping animated batches that slide cells around) while carrying the update
/// stage's source-shaped data separately, since reconfigures resolve synchronously at
/// source-coordinate index paths.
@MainActor
@Suite("Chat changeset single-batch plan")
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

    @Test("A send (previous-row update + insert) merges into one batch carrying the update stage's data")
    func updateAndInsert_mergesIntoOneBatch() throws {
        // A new own message migrates the receipt off the previous row and flips its grouping —
        // an update — while the new row is an insert. DifferenceKit stages these separately.
        let before = [message("a", receipt: "Delivered")]
        let after = [
            message("a", continuedByNext: true),
            message("b", continuationFromPrevious: true, receipt: "Delivered"),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 2, "premise: DifferenceKit stages [updates]+[inserts] separately")

        let batch = try #require(staged.singleBatch())
        #expect(batch.changeset.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(batch.changeset.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(batch.changeset.elementDeleted.isEmpty)
        #expect(batch.changeset.elementMoved.isEmpty)
        #expect(batch.changeset.data == after)
        // The reconfigure resolves against the source shape holding the updated row's new content.
        #expect(batch.reconfigureData == [after[0]])
    }

    @Test("An arrival while typing (update + delete + insert) merges into one batch")
    func updateDeleteAndInsert_mergesIntoOneBatch() throws {
        // The typing indicator clears (delete), the reply lands (insert), and the previous row's
        // grouping flips (update) — three DifferenceKit stages in one push.
        let before = [message("a", sender: .other), .typingIndicator]
        let after = [
            message("a", sender: .other, continuedByNext: true),
            message("b", sender: .other, continuationFromPrevious: true),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 3, "premise: DifferenceKit stages [updates]+[deletes]+[inserts] separately")

        let batch = try #require(staged.singleBatch())
        #expect(batch.changeset.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(batch.changeset.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(batch.changeset.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(batch.changeset.elementMoved.isEmpty)
        #expect(batch.changeset.data == after)
        #expect(batch.reconfigureData == [after[0], .typingIndicator])
    }

    @Test("A pure delete + insert pair merges with no reconfigure data")
    func deleteAndInsert_mergesWithoutReconfigureData() throws {
        // The pre-existing behavior (typing indicator swaps for a message with no other change).
        let before = [message("a", sender: .other), .typingIndicator]
        let after = [message("a", sender: .other), message("b", sender: .other)]

        let batch = try #require(StagedChangeset(source: before, target: after).singleBatch())
        #expect(batch.changeset.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(batch.changeset.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(batch.changeset.data == after)
        #expect(batch.reconfigureData == nil)
    }

    @Test("Stages containing moves get no single batch")
    func moves_getNoSingleBatch() {
        // A move's source index is relative to the post-delete stage, not the original source, so
        // merging would corrupt indices. Reorders never happen in a transcript; keep them staged.
        let before = [message("a"), message("b")]
        let after = [message("b"), .message(ChatMessage(id: "a", text: "edited", sender: .me))]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.contains { !$0.elementMoved.isEmpty }, "premise: a reorder diffs to a move")

        #expect(staged.singleBatch() == nil)
    }
}
