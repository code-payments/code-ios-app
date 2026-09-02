//
//  ConversationController+MessageMutations.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.conversation-controller")

/// What a mutation attempt did.
enum MutationOutcome: Equatable {
    /// The server accepted it; the transcript shows the result.
    case applied
    /// Another client's change won; the transcript shows that change instead.
    case conflicted
    /// Nothing applied; the transcript has reverted to what it showed before.
    case failed
}

@MainActor
extension ConversationController {

    /// Replaces a message's text. The transcript updates immediately from an overlay; the server's
    /// answer then replaces it, whether that answer is the edit or somebody else's.
    @discardableResult
    func edit(messageID: MessageID, in conversationID: ConversationID, to text: String) async -> MutationOutcome {
        guard let current = confirmedMessage(messageID, in: conversationID), current.eventSequence > 0 else {
            logger.error("Refusing to edit a message with no confirmed sequence", metadata: [
                "conversationID": "\(conversationID)",
                "messageID": "\(messageID)",
            ])
            return .failed
        }

        store.applyMutation(
            MutationEntry(messageID: messageID, kind: .edited(text), expectedSequence: current.eventSequence),
            in: conversationID
        )
        bumpMessageRevision()

        do {
            let outcome = try await messaging.editMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                expectedEventSequence: current.eventSequence
            )
            settle(outcome, messageID: messageID, in: conversationID, operation: "edit-message")
            if outcome.isConflict {
                mutationAlert = MutationAlert(action: .edit, kind: .conflict)
                return .conflicted
            }
            return .applied
        } catch {
            store.dropMutation(for: messageID, in: conversationID)
            bumpMessageRevision()
            logger.error("Failed to edit conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to edit conversation message")
            mutationAlert = MutationAlert(action: .edit, kind: .failure)
            return .failed
        }
    }

    /// Deletes a message for everyone in the conversation. The row is not removed — it becomes a
    /// tombstone, so message ordering stays gapless and a reply quoting it still has a target.
    @discardableResult
    func delete(messageID: MessageID, in conversationID: ConversationID) async -> MutationOutcome {
        guard let current = confirmedMessage(messageID, in: conversationID), current.eventSequence > 0 else {
            logger.error("Refusing to delete a message with no confirmed sequence", metadata: [
                "conversationID": "\(conversationID)",
                "messageID": "\(messageID)",
            ])
            return .failed
        }

        store.applyMutation(
            MutationEntry(messageID: messageID, kind: .deleted, expectedSequence: current.eventSequence),
            in: conversationID
        )
        bumpMessageRevision()

        do {
            let outcome = try await messaging.deleteMessage(
                owner: owner,
                conversationID: conversationID,
                messageID: messageID,
                expectedEventSequence: current.eventSequence
            )
            settle(outcome, messageID: messageID, in: conversationID, operation: "delete-message")
            if outcome.isConflict {
                mutationAlert = MutationAlert(action: .delete, kind: .conflict)
                return .conflicted
            }
            return .applied
        } catch {
            store.dropMutation(for: messageID, in: conversationID)
            bumpMessageRevision()
            logger.error("Failed to delete conversation message", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to delete conversation message")
            mutationAlert = MutationAlert(action: .delete, kind: .failure)
            return .failed
        }
    }

    /// The stored copy. The overlay is deliberately not consulted: `expected_event_sequence` has to
    /// come from server truth, or a second edit would send the sequence the first one optimistically
    /// assumed and conflict against the server every time.
    private func confirmedMessage(_ messageID: MessageID, in conversationID: ConversationID) -> ConversationMessage? {
        do {
            return try database.message(id: messageID, conversationID: conversationID)
        } catch {
            logger.error("Failed to read message for mutation", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            return nil
        }
    }

    /// Persists whatever the server says the message now is and drops the overlay. Identical for an
    /// accepted mutation and a conflict — a conflict's payload is the state that won, which is
    /// exactly what has to land locally. There is no retry: reissuing would clobber the change that
    /// beat this one.
    private func settle(
        _ outcome: MessageMutation,
        messageID: MessageID,
        in conversationID: ConversationID,
        operation: String
    ) {
        _ = persist(operation: operation) {
            try database.upsertConversationMessages([outcome.message], conversationID: conversationID)
        }
        store.dropMutation(for: messageID, in: conversationID)
        refreshFeedPreview(for: conversationID)
        persistConversation(conversationID)
    }
}
