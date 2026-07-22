//
//  SendTarget.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Who a direct send pays: a synced contact (resolved by phone, posted into
/// the contact DM) or a tip recipient (resolved by user id, posted into the
/// tip DM — no contact information involved).
nonisolated enum SendTarget: Hashable, Sendable {
    case contact(ResolvedContact)
    case tip(TipRecipient)
}

/// A tip recipient as scanned from a tipcode or opened from a tipcard link.
nonisolated struct TipRecipient: Hashable, Sendable {
    let userID: UserID
    let displayName: String
}

extension SendTarget {

    /// The send target a conversation's counterpart resolves to: the tip
    /// recipient for a tip DM, otherwise the counterpart's shared phone
    /// number. `nil` when neither identifies someone payable. The one rule
    /// the thread's `$` button and the Send Cash push action share.
    @MainActor
    init?(conversation: Conversation?, dmChatID: Data, selfUserID: UserID) {
        switch conversation?.type {
        case .tipDm:
            guard let counterpart = conversation?.counterpart(excluding: selfUserID),
                  let userID = counterpart.userID else {
                return nil
            }
            self = .tip(TipRecipient(userID: userID, displayName: counterpart.displayName))
        case .contactDm, nil:
            guard let target = ResolvedContact.sendTarget(
                in: conversation,
                dmChatID: dmChatID,
                selfUserID: selfUserID
            ) else {
                return nil
            }
            self = .contact(target)
        }
    }
}
