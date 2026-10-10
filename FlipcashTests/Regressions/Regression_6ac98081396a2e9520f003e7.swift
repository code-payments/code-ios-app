//
//  Regression_6ac98081396a2e9520f003e7.swift
//  Flipcash
//
//  Crash: String.index(before:) traps in MentionTrigger.query(in:cursor:) when the
//         composer's selection sits inside the draft's first Character, such as the
//         middle of an emoji, which the TextField binding can leave for one layout pass.
//
//  Fix: query(in:cursor:) returns nil for a cursor that is not a Character boundary.
//

import SwiftUI
import Testing
@testable import Flipcash

@MainActor
@Suite("Regression: 6ac9808 – mention query traps on a cursor inside a Character", .bug("6ac98081396a2e9520f003e7"))
struct Regression_6ac9808 {

    /// Drafts paired with a cursor strictly inside their first `Character`.
    nonisolated static let misaligned: [(String, String.Index)] = [
        ("😂", "😂".utf8.index("😂".utf8.startIndex, offsetBy: 2)),
        ("❤️", String.Index(utf16Offset: 1, in: "❤️")),
    ]

    @Test("A cursor inside the draft's first Character closes the mention picker", arguments: misaligned)
    func misalignedCursor_closesPicker(draft: String, cursor: String.Index) {
        let composer = ComposerModel()
        composer.draft = draft
        composer.selection = TextSelection(insertionPoint: cursor)

        #expect(composer.mentionQuery == nil)
    }
}
