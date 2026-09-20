//
//  ComposerModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

/// What the composer is writing, and the text it holds. Editing borrows the same field as a new
/// message, so the unsent draft is stashed while an edit is in progress and put back if the edit is
/// cancelled.
@MainActor
@Observable
final class ComposerModel {

    /// What a reply is composed against — enough to render the strip and to address the send,
    /// so the composer never reaches back into the transcript for it.
    struct ReplyTarget: Equatable {
        let messageID: MessageID
        let stableID: String
        let authorName: String
        /// The author's user id, carried only so the strip can draw them in their own colour — see
        /// `ComplementaryPalette`.
        let authorID: UserID?
        let snippet: String
        /// What the original was, so the strip can draw a payment the way the transcript's quote
        /// panel does — flag and token beside the amount, rather than the amount alone.
        var kind: ChatQuote.Kind = .text
    }

    enum Mode: Equatable {
        case new
        /// `stableID` is the transcript row's identity, kept alongside the message id so the screen
        /// can highlight the row being edited without re-deriving it.
        case editing(messageID: MessageID, stableID: String)
        case replying(to: ReplyTarget)
    }

    private(set) var mode: Mode = .new
    var draft = ""

    /// The unsent new-message draft, held while an edit occupies the field.
    @ObservationIgnored private var stashedDraft = ""
    /// The text the message had when the edit began, so an unchanged edit can be refused.
    @ObservationIgnored private var originalText = ""

    /// The trimmed text to submit, or `nil` if there is nothing worth submitting. An edit that
    /// matches the original is nothing worth submitting.
    var submission: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch mode {
        case .new, .replying:
            return trimmed
        case .editing:
            return trimmed == originalText ? nil : trimmed
        }
    }

    var canSubmit: Bool { submission != nil }

    /// The transcript row an edit is open on, if any. The chat screen keys its edit backdrop off
    /// this, so reading it is what ties the backdrop's lifetime to the composer's mode.
    var editingStableID: String? {
        switch mode {
        case .new, .replying:               nil
        case .editing(_, let stableID):     stableID
        }
    }

    /// The message this composer is replying to, or `nil` when it is not replying.
    var replyTarget: ReplyTarget? {
        switch mode {
        case .new, .editing:            nil
        case .replying(let target):     target
        }
    }

    /// Whether the field is editing an existing message rather than writing a new one. The bar
    /// swaps its leading control and its confirm glyph on this.
    var isEditing: Bool {
        switch mode {
        case .new, .replying:   false
        case .editing:          true
        }
    }

    /// What is worth persisting for this chat. While an edit occupies the field that is the
    /// new-message draft the edit displaced, never the edit body — leaving mid-edit must not
    /// overwrite your own words with someone else's message.
    ///
    /// Whether it is stored at all is the draft store's call; this only says what it holds.
    var persistableDraft: ChatDraft {
        switch mode {
        case .new:
            ChatDraft(text: draft, replyTarget: nil)
        case .replying(let target):
            ChatDraft(text: draft, replyTarget: ChatDraft.ReplyTarget(target))
        case .editing:
            ChatDraft(text: stashedDraft, replyTarget: nil)
        }
    }

    /// Puts a stored draft back into an untouched composer. Silent by design: the text and the
    /// strip come back, focus and the keyboard do not — the keyboard opens only for post-tip
    /// navigation, and a restored draft must not change that.
    ///
    /// Refused once anything has been typed or an edit has begun, so a restore that arrives late
    /// cannot overwrite what the user is already writing.
    func restore(_ stored: ChatDraft) {
        guard case .new = mode, draft.isEmpty else { return }
        draft = stored.text
        if let target = stored.replyTarget {
            mode = .replying(to: ReplyTarget(target))
        }
    }

    /// Switches the field to editing an existing message, stashing whatever was being written.
    ///
    /// Stashed out of a reply as well as out of a new message. The field is single-mode, so the
    /// strip goes when the edit takes it — but the words in the field are the user's own, and only
    /// an edit already in progress has nothing of theirs left to displace.
    func beginEditing(messageID: MessageID, stableID: String, currentText: String) {
        if !isEditing {
            stashedDraft = draft
        }
        mode = .editing(messageID: messageID, stableID: stableID)
        originalText = currentText
        draft = currentText
    }

    /// Leaves editing and restores the stashed draft.
    func endEditing() {
        guard case .editing = mode else { return }
        mode = .new
        originalText = ""
        draft = stashedDraft
        stashedDraft = ""
    }

    /// Aims the composer at a message. Unlike an edit, the draft is left alone — a reply adds to
    /// what you were already typing rather than replacing it.
    func beginReplying(to target: ReplyTarget) {
        if isEditing { endEditing() }
        mode = .replying(to: target)
    }

    /// Dismisses the reply, keeping the draft — the strip's ⊗ takes back the target, not the text.
    func endReplying() {
        guard case .replying = mode else { return }
        mode = .new
    }

    /// Empties the field after a successful send.
    func clear() {
        // Only when it actually changes. `@Observable` fires on assignment without comparing, and
        // the chat screen's body reads `isEditing` and `editingStableID` — both derived from this —
        // so writing `.new` over `.new` on every send rebuilt the whole screen and re-ran
        // `updateUIViewController` at the frame the insertion animation started.
        if mode != .new {
            mode = .new
        }
        originalText = ""
        stashedDraft = ""
        draft = ""
    }
}
