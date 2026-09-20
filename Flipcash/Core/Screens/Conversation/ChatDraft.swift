//
//  ChatDraft.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// A half-written message kept for a chat: what was typed, and what it was aimed at.
///
/// Content only, so `==` means "the same draft" — which is what a failed send's compare-and-delete
/// asks. When the draft was written is the store's business and lives on the store's own row.
struct ChatDraft: Equatable, Codable, Sendable {

    /// The reply strip's own snapshot, mirroring ``ComposerModel/ReplyTarget`` in a form that can be
    /// written to disk. The strip is drawn from this rather than from the transcript, so a draft
    /// restores its context even when the cited message is outside the loaded window.
    struct ReplyTarget: Equatable, Codable, Sendable {
        /// The raw message id. Stored unwrapped because `MessageID` is a `FlipcashCore` type and
        /// persistence is this layer's concern, not its.
        let messageID: UInt64
        let stableID: String
        let authorName: String
        let authorID: UserID?
        let snippet: String
        let kind: ChatQuote.Kind
    }

    var text: String
    var replyTarget: ReplyTarget?

    /// Whether this is worth a row at all. Trimmed-empty text with nothing aimed is a cleared
    /// composer, and storing it would restore an empty draft for ever — rule 2.
    var isWorthKeeping: Bool {
        replyTarget != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ChatDraft.ReplyTarget {
    init(_ target: ComposerModel.ReplyTarget) {
        self.init(
            messageID: target.messageID.value,
            stableID: target.stableID,
            authorName: target.authorName,
            authorID: target.authorID,
            snippet: target.snippet,
            kind: target.kind
        )
    }
}

extension ComposerModel.ReplyTarget {
    init(_ target: ChatDraft.ReplyTarget) {
        self.init(
            messageID: MessageID(value: target.messageID),
            stableID: target.stableID,
            authorName: target.authorName,
            authorID: target.authorID,
            snippet: target.snippet,
            kind: target.kind
        )
    }
}
