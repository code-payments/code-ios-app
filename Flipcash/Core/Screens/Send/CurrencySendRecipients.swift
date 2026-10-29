//
//  CurrencySendRecipients.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Who Currency Info's Select Recipient step lists: the chat list's 1:1 chats, in the chat list's
/// order, narrowed by a search over name and username. Groups never appear, and neither do the
/// device's contacts — this is a view of the chat list, not an address book.
nonisolated enum CurrencySendRecipients {

    /// `chats` is the chat list as it is drawn; `name` is how a row titles a chat.
    static func recipients(
        in chats: [Conversation],
        query: String,
        selfUserID: UserID?,
        name: (Conversation) -> String
    ) -> [Conversation] {
        let direct = chats.filter { $0.type != .group }
        let needle = normalized(query)
        guard !needle.isEmpty else { return direct }
        return direct.filter { chat in
            if name(chat).lowercased().contains(needle) { return true }
            let handle = chat.counterpart(excluding: selfUserID)?.username?.value ?? ""
            return handle.contains(needle)
        }
    }

    /// Lowercased, trimmed, and without the `@` people type before a handle.
    private static func normalized(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("@") { text.removeFirst() }
        return text
    }
}
