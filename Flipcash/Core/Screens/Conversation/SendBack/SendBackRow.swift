//
//  SendBackRow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Which Send Back row a cash message draws, from the transcript and what this DM open has learned
/// about the offer. Pure, so the mapper and the tests share it.
enum SendBackRow {

    /// What this open knows about an offered message's return, as ``SendBackController`` tracks it.
    enum Local: Equatable, Sendable {
        /// No status yet: never asked, in flight, or the check failed. The row stays hidden.
        case unknown
        /// The server says the payment can still be sent back.
        case available
        /// The receiver swiped and the return has not resolved.
        case sending
        /// The return landed, or the server says it already had.
        case sentBack
    }

    /// The row for `message`: Sent Back on either side once a message in the transcript returns it,
    /// else the receiver's view of an open offer. The sender of an offer never sees Send Back.
    nonisolated static func resolve(
        _ message: ConversationMessage,
        selfUserID: UserID,
        returnedIDs: Set<MessageID>,
        local: Local
    ) -> ChatCashContent.SendBack? {
        guard case .cash = message.content else { return nil }
        if returnedIDs.contains(message.id) { return .sentBack }
        guard isOffered(message, to: selfUserID) else { return nil }
        switch local {
        case .unknown:   return nil
        case .available: return .available
        case .sending:   return .sending
        case .sentBack:  return .sentBack
        }
    }

    /// Whether `message` offers `viewer` a return: a cash message carrying an offer whose single
    /// receiver is the viewer. Only that viewer sees Send Back or asks the server about it.
    nonisolated static func isOffered(_ message: ConversationMessage, to viewer: UserID) -> Bool {
        guard case .cash = message.content,
              message.cashReturn?.hasOffer == true,
              message.cashReceiverID == viewer,
              !message.isFromSelf(viewer) else { return false }
        return true
    }

    /// The messages a message in `window` returns. A return is always later in the DM than the
    /// message it returns, so a loaded original always has its return loaded too.
    nonisolated static func returnedIDs(in window: [ConversationMessage]) -> Set<MessageID> {
        Set(window.compactMap { $0.cashReturn?.returnOf?.messageID })
    }

    /// Whether this open should ask the server about `message`: it is offered to the viewer and
    /// nothing in the transcript returns it yet.
    nonisolated static func needsStatus(_ message: ConversationMessage, selfUserID: UserID, returnedIDs: Set<MessageID>) -> Bool {
        isOffered(message, to: selfUserID) && !returnedIDs.contains(message.id)
    }
}
