//
//  FailedSendDrafts.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Keeps the words of a send that failed.
///
/// Sending clears the draft because the text then lives in the pending message — which is safe only
/// while that message outlives the same navigation the draft would have. Here it does not:
/// `SendStatus` says `.sending` and `.failed` "exist only for an optimistic message in flight on
/// this device this session", and the message schema has no send-status column. A failed send that
/// is popped, backgrounded out of, or relaunched past takes the text with it.
///
/// So a failure puts the draft back where submit took it from, and a retry that lands takes it away
/// again. Android needs none of this: its failed message is a persisted row with its own retry.
@MainActor
final class FailedSendDrafts {

    private struct Entry {
        let conversationID: ConversationID
        let draft: ChatDraft
        /// Whether the draft was actually written back. A send that has not failed has nothing in
        /// the store to take away on success.
        var isRestored = false
    }

    private let store: ChatDraftStore
    private var inFlight: [UUID: Entry] = [:]

    init(store: ChatDraftStore) {
        self.store = store
    }

    /// Remembers what a send is carrying, in case it does not land. The draft is the composer's
    /// own — untrimmed text and the whole reply strip — captured before the field was cleared.
    func willSend(_ draft: ChatDraft, clientMessageID: UUID, in conversationID: ConversationID) {
        inFlight[clientMessageID] = Entry(conversationID: conversationID, draft: draft)
    }

    /// Puts the text back after a failure, unless the chat already holds a newer draft: the user
    /// typed on, and the failed bubble is still on screen with its own retry.
    func didFail(clientMessageID: UUID) {
        guard var entry = inFlight[clientMessageID], !entry.isRestored else { return }
        guard store.draft(for: entry.conversationID) == nil else { return }
        store.save(entry.draft, for: entry.conversationID)
        entry.isRestored = true
        inFlight[clientMessageID] = entry
    }

    /// Takes the restored draft away once the retry lands. Compare-and-delete, so a draft typed
    /// while the retry was in flight is not eaten by it.
    func didSucceed(clientMessageID: UUID) {
        guard let entry = inFlight.removeValue(forKey: clientMessageID), entry.isRestored else { return }
        guard store.draft(for: entry.conversationID) == entry.draft else { return }
        store.remove(for: entry.conversationID)
    }

    /// Forgets a send without touching the store — the message was dropped rather than delivered.
    func forget(clientMessageID: UUID) {
        inFlight[clientMessageID] = nil
    }
}
