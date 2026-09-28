//
//  ComposerModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
import Observation
import SwiftUI
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

    /// The most photos one send can carry, matching `chat_media.json`'s `maxAttachments`.
    static let maxAttachments = 10

    private(set) var mode: Mode = .new
    var draft = ""
    /// The field's cursor or selection, while it has focus.
    ///
    /// Cleared wherever the draft is replaced wholesale: its indices belong to the text it was
    /// taken from.
    var selection: TextSelection?

    /// Photos staged for the next send, in the order they were added.
    private(set) var chips: [ComposerChip] = []

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

    /// Whether the send button can fire: text or at least one chip, and no chip that failed. Chips
    /// still uploading do not hold the send back, and an edit is text only.
    var canSubmit: Bool {
        switch mode {
        case .new, .replying:
            !hasFailedChip && (submission != nil || !chips.isEmpty)
        case .editing:
            submission != nil
        }
    }

    /// What the send button posts for a new message or a reply.
    enum Outgoing {
        case text(String)
        /// The staged photos in order, with the trimmed text as the caption.
        case media([ComposerChip], caption: String?)
    }

    /// What the send button would post now, or `nil` when it cannot fire or the field holds an edit.
    var outgoing: Outgoing? {
        switch mode {
        case .editing:
            return nil
        case .new, .replying:
            guard canSubmit else { return nil }
            if chips.isEmpty {
                return submission.map(Outgoing.text)
            }
            return .media(chips, caption: submission)
        }
    }

    /// Whether any staged chip failed to upload, which holds the send until it is retried or removed.
    var hasFailedChip: Bool {
        chips.contains { chip in
            switch chip.state {
            case .failed:                               true
            case .preparing, .uploading, .uploaded:     false
            }
        }
    }

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
        selection = nil
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
        selection = nil
    }

    /// Leaves editing and restores the stashed draft.
    func endEditing() {
        guard case .editing = mode else { return }
        mode = .new
        originalText = ""
        draft = stashedDraft
        selection = nil
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

    /// Stages `image` as a new chip, drawn from `preview` until its thumbnail is ready, and starts its
    /// upload through `uploader`, returning the chip, or returns `nil` when the composer already
    /// holds `maxAttachments` chips.
    @discardableResult
    func stageChip(image: UIImage, preview: UIImage? = nil, uploader: ChatMediaUploader) -> ComposerChip? {
        guard chips.count < Self.maxAttachments else { return nil }
        let chip = ComposerChip(image: image, preview: preview)
        chips.append(chip)
        chip.startUpload(using: uploader)
        return chip
    }

    /// Drops the chip with `id` and cancels its upload.
    func removeChip(_ id: ComposerChip.ID) {
        guard let index = chips.firstIndex(where: { $0.id == id }) else { return }
        chips[index].uploadTask?.cancel()
        chips.remove(at: index)
    }

    /// Empties the field and the chip strip once a send has taken them. The chips' uploads keep
    /// running, since the send awaits them.
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
        selection = nil
        if !chips.isEmpty {
            chips = []
        }
    }

    /// The `@word` at the cursor that the mention picker searches for, or `nil` when it is closed.
    var mentionQuery: MentionQuery? {
        MentionTrigger.query(in: draft, selection: selection)
    }

    /// Replaces the `@word` at the cursor with `@username ` and puts the cursor after it, as if it
    /// had been typed.
    func insertMention(username: String) {
        guard let query = mentionQuery else { return }
        let result = MentionTrigger.inserting(username: username, replacing: query, in: draft)
        draft = result.text
        selection = TextSelection(insertionPoint: result.cursor)
    }
}
