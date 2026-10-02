//
//  RosterSearchSource.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// A group member a roster search matched.
nonisolated struct MemberMatch: Identifiable, Hashable, Sendable {
    let member: ConversationMember
    let id: UserID
}

/// Searches a group's members by name or username, for the mention picker.
///
/// Callers depend on this rather than on a concrete search so the source of members can change
/// without them changing.
protocol RosterSearchSource: AnyObject {
    /// Readies the source to answer for a group; called when the picker opens. Returns `false` when
    /// it couldn't, so the caller keeps its current results rather than searching again.
    @discardableResult
    func prepare(chatID: ConversationID) async -> Bool

    /// Returns up to `limit` members of a group matching `query`, best match first, never a blocked
    /// user. An empty query matches everyone the source holds.
    func search(chatID: ConversationID, query: String, limit: Int) async throws -> [MemberMatch]
}

extension RosterSearchSource {
    /// Returns up to 20 members of a group matching `query`; see ``search(chatID:query:limit:)``.
    func search(chatID: ConversationID, query: String) async throws -> [MemberMatch] {
        try await search(chatID: chatID, query: query, limit: 20)
    }
}
