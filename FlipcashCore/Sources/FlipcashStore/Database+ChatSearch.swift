//
//  Database+ChatSearch.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import SQLite

/// A stored message paired with the conversation it belongs to, as read for local search.
public struct SearchableMessage: Sendable {
    public let conversationID: ConversationID
    public let message: ConversationMessage

    public init(conversationID: ConversationID, message: ConversationMessage) {
        self.conversationID = conversationID
        self.message = message
    }
}

nonisolated extension Database {

    /// Every stored message whose content can carry searchable text (decrypted text, media, the
    /// share-profile widget), newest first, read off the caller's actor.
    public func searchableMessages() async throws -> [SearchableMessage] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try self.getSearchableMessages())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Synchronous form of ``searchableMessages()``.
    public func getSearchableMessages() throws -> [SearchableMessage] {
        let m = ConversationMessageTable()
        // Kinds 0 (text), 4 (widget) and 5 (media); cash, deleted, encrypted and system rows carry
        // no user-authored text.
        let rows = try reader.prepareRowIterator(
            m.table.filter([0, 4, 5].contains(m.kind)).order(m.date.desc)
        )
        return try rows.compactMap { row in
            conversationMessage(from: row).map {
                SearchableMessage(conversationID: ConversationID(data: row[m.conversationId]), message: $0)
            }
        }
    }
}
