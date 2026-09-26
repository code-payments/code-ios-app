//
//  SendTarget.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Who a send pays: a synced contact (resolved by phone, posted into the
/// contact DM), a tip recipient (resolved by user id, posted into the tip DM —
/// no contact information involved), or a group chat, which gets a cash link
/// that its first claimant takes.
nonisolated enum SendTarget: Hashable, Sendable {
    case contact(ResolvedContact)
    case tip(TipRecipient)
    case group(ConversationID)
}

/// A tip recipient as scanned from a tipcode or opened from a tipcard link.
nonisolated struct TipRecipient: Hashable, Sendable {
    let userID: UserID
    let displayName: String
    /// The recipient's public handle, shown under their name on the card.
    /// Defaulted for the test fixtures only — both production sites pass one.
    let username: Username?
    /// The surface this tip is being sent from — reported to the server.
    let origin: TipOrigin

    // A hand-written init rather than the synthesized memberwise one: a `let`
    // with an inline default loses its parameter entirely (the default becomes
    // fixed, unoverridable), so the default has to live here instead to stay
    // both immutable and omittable by the fixtures that don't supply one.
    init(userID: UserID, displayName: String, username: Username? = nil, origin: TipOrigin) {
        self.userID = userID
        self.displayName = displayName
        self.username = username
        self.origin = origin
    }
}

extension SendTarget {

    /// The send target a conversation resolves to: the tip recipient for a tip
    /// DM, the chat itself for a group, otherwise the counterpart's shared
    /// phone number. `nil` when none identifies someone payable. The one rule
    /// the thread's `$` button and the Send Cash push action share.
    @MainActor
    init?(conversation: Conversation?, dmChatID: Data, selfUserID: UserID) {
        switch conversation?.type {
        case .tipDm:
            guard let counterpart = conversation?.counterpart(excluding: selfUserID),
                  let userID = counterpart.userID else {
                return nil
            }
            self = .tip(TipRecipient(userID: userID, displayName: counterpart.displayName, username: counterpart.username, origin: .chat))
        case .contactDm, nil:
            guard let target = ResolvedContact.sendTarget(
                in: conversation,
                dmChatID: dmChatID,
                selfUserID: selfUserID
            ) else {
                return nil
            }
            self = .contact(target)
        case .group:
            guard let conversation else { return nil }
            self = .group(conversation.id)
        }
    }
}
