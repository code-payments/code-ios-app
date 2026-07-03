//
//  ChatChangesetFlatteningTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
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

    @Test("A send (previous-row update + insert) flattens to a single changeset")
    func updateAndInsert_flattensToOne() throws {
        // A new own message migrates the receipt off the previous row and flips its grouping —
        // an update — while the new row is an insert. DifferenceKit stages these separately.
        let before: [ChatItem] = [.text("a", receipt: "Delivered")]
        let after: [ChatItem] = [
            .text("a", continuedByNext: true),
            .text("b", continuationFromPrevious: true, receipt: "Delivered"),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 2, "premise: DifferenceKit stages [updates]+[inserts] separately")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == 1)
        let merged = try #require(flattened.first)
        #expect(merged.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementDeleted.isEmpty)
        #expect(merged.elementMoved.isEmpty)
        #expect(merged.data == after)
    }

    @Test("An arrival while typing (update + delete + insert) flattens to a single changeset")
    func updateDeleteAndInsert_flattensToOne() throws {
        // The typing indicator clears (delete), the reply lands (insert), and the previous row's
        // grouping flips (update) — three DifferenceKit stages in one push.
        let before: [ChatItem] = [.text("a", sender: .other), .typingIndicator]
        let after: [ChatItem] = [
            .text("a", sender: .other, continuedByNext: true),
            .text("b", sender: .other, continuationFromPrevious: true),
        ]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.count == 3, "premise: DifferenceKit stages [updates]+[deletes]+[inserts] separately")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == 1)
        let merged = try #require(flattened.first)
        #expect(merged.elementUpdated == [ElementPath(element: 0, section: 0)])
        #expect(merged.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementMoved.isEmpty)
        #expect(merged.data == after)
    }

    @Test("A pure delete + insert pair still flattens to a single changeset")
    func deleteAndInsert_stillFlattensToOne() throws {
        // The pre-existing behavior (typing indicator swaps for a message with no other change).
        let before: [ChatItem] = [.text("a", sender: .other), .typingIndicator]
        let after: [ChatItem] = [.text("a", sender: .other), .text("b", sender: .other)]

        let flattened = StagedChangeset(source: before, target: after).flattenIfPossible()
        #expect(flattened.count == 1)
        let merged = try #require(flattened.first)
        #expect(merged.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.data == after)
    }

    @Test("Stages containing moves are left un-flattened")
    func moves_areNotFlattened() {
        // A move's source index is relative to the post-delete stage, not the original source, so
        // merging would corrupt indices. Reorders never happen in a transcript; keep them staged.
        let before: [ChatItem] = [.text("a"), .text("b")]
        let after: [ChatItem] = [.text("b"), .message(ChatMessage(id: "a", text: "edited", sender: .me))]

        let staged = StagedChangeset(source: before, target: after)
        #expect(staged.contains { !$0.elementMoved.isEmpty }, "premise: a reorder diffs to a move")

        let flattened = staged.flattenIfPossible()
        #expect(flattened.count == staged.count)
        #expect(flattened.contains { !$0.elementMoved.isEmpty })
    }

    @Test("A same-id cell-class swap (text gains a link) stays a replace through flattening")
    func classSwapSameID_staysReplace() throws {
        // The diff identity folds in the cell class, so a message whose class changes must diff
        // as delete + insert — a reconfigure landing on a different cell class is a UIKit crash.
        let before: [ChatItem] = [.text("a"), .text("b")]
        let after: [ChatItem] = [
            .text("a"),
            .text("b", linkPreview: LinkPreview(url: URL(string: "https://flipcash.com")!)),
        ]

        let flattened = StagedChangeset(source: before, target: after).flattenIfPossible()
        #expect(flattened.count == 1)
        let merged = try #require(flattened.first)
        #expect(merged.elementUpdated.isEmpty, "a class change must never reconfigure")
        #expect(merged.elementDeleted == [ElementPath(element: 1, section: 0)])
        #expect(merged.elementInserted == [ElementPath(element: 1, section: 0)])
        #expect(merged.data == after)
    }
}
