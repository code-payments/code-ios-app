//
//  MentionTrigger.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI

/// The `@word` a mention picker is searching for: where it sits in the draft and what follows its `@`.
nonisolated struct MentionQuery: Equatable, Sendable {

    /// The word's range in the draft, `@` included.
    let range: Range<String.Index>

    /// The text after the `@`, as typed.
    let text: String
}

/// Decides whether the draft is asking for a mention, and writes a picked one back into it.
nonisolated enum MentionTrigger {

    /// The characters that open the picker. The fullwidth form counts too, for parity with Android.
    static let triggers: Set<Character> = ["@", "＠"]

    /// The mention being typed at `selection`, or `nil` when the picker should be closed.
    ///
    /// Open only for a collapsed cursor at the end of a whitespace-free word that starts with a
    /// trigger. The word stops at whitespace, so its `@` always stands at the start of the text or
    /// after whitespace, and `a@b` is not a mention.
    static func query(in text: String, selection: TextSelection?) -> MentionQuery? {
        guard let selection else { return nil }
        switch selection.indices {
        case .selection(let range):
            guard range.isEmpty else { return nil }
            return query(in: text, cursor: range.lowerBound)
        case .multiSelection:
            return nil
        @unknown default:
            return nil
        }
    }

    /// The mention being typed before `cursor`, or `nil` when there is none.
    static func query(in text: String, cursor: String.Index) -> MentionQuery? {
        guard cursor >= text.startIndex, cursor <= text.endIndex else { return nil }
        var start = cursor
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard !text[previous].isWhitespace else { break }
            start = previous
        }
        guard start < cursor, triggers.contains(text[start]) else { return nil }
        let range = start..<cursor
        return MentionQuery(range: range, text: String(text[text.index(after: start)..<cursor]))
    }

    /// `text` with `query`'s word replaced by `@username ` as plain text, and the cursor after the
    /// space.
    ///
    /// Always the ASCII `@`, whichever trigger was typed: only that form is detected as a mention
    /// once the message is sent.
    static func inserting(
        username: String,
        replacing query: MentionQuery,
        in text: String
    ) -> (text: String, cursor: String.Index) {
        let inserted = "@\(username) "
        var result = text
        result.replaceSubrange(query.range, with: inserted)
        let offset = text.distance(from: text.startIndex, to: query.range.lowerBound) + inserted.count
        return (result, result.index(result.startIndex, offsetBy: offset))
    }
}

/// How many suggestion rows the list may show.
nonisolated enum MentionRowCap {

    /// The most rows with no reply open.
    static let rows = 4

    /// The most rows with a reply open, which already takes a card's worth of the bar.
    static let rowsWithReply = 3

    /// The fewest rows the cap drops to when the transcript runs short.
    static let fallbackRows = 2

    /// The transcript height the list must leave above it before it falls back.
    static let minimumTranscript: CGFloat = 120

    /// The row count for a list whose rows are `rowHeight` tall and whose padding and ground add
    /// `chrome`, given `room`: the transcript's height without the list. Unmeasured room keeps the
    /// full count.
    static func rows(replyOpen: Bool, room: CGFloat?, rowHeight: CGFloat, chrome: CGFloat) -> Int {
        let full = replyOpen ? rowsWithReply : rows
        guard let room else { return full }
        let list = CGFloat(full) * rowHeight + chrome
        return room - list < minimumTranscript ? fallbackRows : full
    }
}
