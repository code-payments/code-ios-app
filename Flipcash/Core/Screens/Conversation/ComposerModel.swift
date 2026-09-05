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

    enum Mode: Equatable {
        case new
        /// `stableID` is the transcript row's identity, kept alongside the message id so the screen
        /// can highlight the row being edited without re-deriving it.
        case editing(messageID: MessageID, stableID: String)
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
        case .new:
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
        case .new:                          nil
        case .editing(_, let stableID):     stableID
        }
    }

    /// Whether the field is editing an existing message rather than writing a new one. The bar
    /// swaps its leading control and its confirm glyph on this.
    var isEditing: Bool {
        switch mode {
        case .new:     false
        case .editing: true
        }
    }

    /// Switches the field to editing an existing message, stashing whatever was being written.
    func beginEditing(messageID: MessageID, stableID: String, currentText: String) {
        if case .new = mode {
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
