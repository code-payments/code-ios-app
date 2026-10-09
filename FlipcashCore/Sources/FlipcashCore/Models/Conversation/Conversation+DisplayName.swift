//
//  Conversation+DisplayName.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

extension Conversation {

    /// Counterpart name shown when neither the synced contacts, the feed, nor a shared phone number
    /// provides one.
    public static let fallbackCounterpartName = "Flipcash User"

    /// The conversation's name: its group title, else the synced contact's address-book name, else
    /// the server-provided member name from the feed, else the counterpart's shared phone number,
    /// else a generic fallback.
    ///
    /// `contactName` is asked for the chat's id and may return nil or an empty string. Tip DMs skip
    /// it — their derived ids can never match a contact's, so the directory scan is a guaranteed miss.
    public func displayName(selfUserID: UserID?, contactName: (ConversationID) -> String?) -> String {
        // Group chats are named by their server-set title, not a counterpart.
        if let title, !title.isEmpty {
            return title
        }
        if type != .tipDm, let name = contactName(id), !name.isEmpty {
            return name
        }
        guard let counterpart = counterpart(excluding: selfUserID) else {
            return Self.fallbackCounterpartName
        }
        if !counterpart.displayName.isEmpty {
            return counterpart.displayName
        }
        return counterpart.formattedPhoneNumber ?? Self.fallbackCounterpartName
    }
}
