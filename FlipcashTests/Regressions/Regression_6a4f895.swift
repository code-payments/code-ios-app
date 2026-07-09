//
//  Regression_6a4f895.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import DifferenceKit
import FlipcashCore
@testable import FlipcashUI

/// A message that keeps its stable id while its content flips to a different cell class (text → cash
/// via a last-writer-wins merge) diffed as an *update*, which the transcript applies as
/// `reconfigureItems` — and UIKit forbids reconfiguring an item into a different cell class
/// (`NSInternalInconsistencyException`: "Dequeued reuse identifier: ChatCashCardCell; Original reuse
/// identifier: ChatMessageCell"). The cell class must be part of the diff identity so a kind change
/// diffs as delete+insert instead.
@MainActor
@Suite("Regression: 6a4f895 – chat transcript reconfigure across cell classes", .bug("6a4f895be96556123e956f79"))
struct Regression_6a4f895 {

    nonisolated private static func text(_ id: String, _ body: String = "hello", link: Bool = false, receipt: String? = nil) -> ChatItem {
        .message(ChatMessage(
            id: id,
            text: body,
            sender: .me,
            receipt: receipt,
            linkPreview: link ? LinkPreview(url: URL(string: "https://example.com")!) : nil
        ))
    }

    nonisolated private static func cash(_ id: String) -> ChatItem {
        .message(ChatMessage(
            id: id,
            content: .cash(ChatCashContent(amount: "$5.00", token: "Cash", flagImageName: "us")),
            sender: .me
        ))
    }

    @Test("A same-id cell-class flip diffs as delete+insert, never an update", arguments: [
        ("text → cash (the crash)", text("m"), cash("m")),
        ("cash → text", cash("m"), text("m")),
        ("plain text → link text (edit gains a URL)", text("m"), text("m", link: true)),
        ("link text → plain text (edit loses it)", text("m", link: true), text("m")),
    ])
    func cellKindFlip_diffsAsReplace(label: String, before: ChatItem, after: ChatItem) {
        let changeset = StagedChangeset(source: [before], target: [after])

        #expect(changeset.flatMap(\.elementUpdated).isEmpty)
        #expect(changeset.flatMap(\.elementDeleted) == [ElementPath(element: 0, section: 0)])
        #expect(changeset.flatMap(\.elementInserted) == [ElementPath(element: 0, section: 0)])
        #expect(changeset.flatMap(\.elementMoved).isEmpty)
    }

    @Test("A same-class content change still diffs as an update, not a replace")
    func sameClassChange_staysAnUpdate() {
        // A receipt tick ("Delivered" → "Read") must remain a cheap in-place reconfigure — guards
        // the fix from over-broadening identity into whole-value equality, which would tear down
        // and re-insert rows on every receipt or grouping change.
        let before = [Self.text("m")]
        let after = [Self.text("m", receipt: "Delivered")]

        let changeset = StagedChangeset(source: before, target: after)

        #expect(changeset.flatMap(\.elementUpdated) == [ElementPath(element: 0, section: 0)])
        #expect(changeset.flatMap(\.elementDeleted).isEmpty)
        #expect(changeset.flatMap(\.elementInserted).isEmpty)
    }
}
