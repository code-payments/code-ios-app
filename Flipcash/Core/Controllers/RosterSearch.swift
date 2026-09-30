//
//  RosterSearch.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

/// A group member a roster search matched.
nonisolated struct MemberMatch: Identifiable, Hashable, Sendable {
    let member: ConversationMember
    let id: UserID
}

/// Searches a group's members by name or username, for the mention picker.
///
/// Callers depend on this rather than on ``LocalRosterSearch`` so a server-side search can replace
/// or back the local one without them changing.
protocol RosterSearchSource: AnyObject {
    /// Readies the source to answer for a group; called when the picker opens.
    func prepare(chatID: ConversationID) async

    /// Returns up to `limit` members of a group matching `query`, best match first, never the
    /// signed-in user. An empty query returns the members who spoke most recently.
    func search(chatID: ConversationID, query: String, limit: Int) async throws -> [MemberMatch]
}

/// Answers roster searches from the roster ``RosterSync`` holds on device.
///
/// A member matches when every word of the query is a prefix of one of their tokens, the words of
/// their display name and their username, compared after ``RosterSearchText/normalize(_:)``. Matches
/// rank in three tiers:
/// 1. members who sent one of the chat's newest held messages, most recent first;
/// 2. the member whose username is exactly the query;
/// 3. everyone else, by normalized display name in code point order.
/// Ties fall to the lowercase user id.
final class LocalRosterSearch: RosterSearchSource {

    /// How many of the chat's newest held messages count toward "spoke recently".
    static let recentMessageWindow = 200

    private let database: Database
    private let roster: RosterSync
    private let selfUserID: UserID

    init(database: Database, roster: RosterSync, selfUserID: UserID) {
        self.database = database
        self.roster = roster
        self.selfUserID = selfUserID
    }

    func prepare(chatID: ConversationID) async {
        await roster.refreshFirstPage(chatID)
    }

    func search(chatID: ConversationID, query: String, limit: Int) async throws -> [MemberMatch] {
        let words = RosterSearchText.queryWords(query)
        let recent = try database.recentSenders(conversationID: chatID, window: Self.recentMessageWindow)

        let candidates: Set<UserID>
        if words.isEmpty {
            candidates = Set(recent)
        } else {
            candidates = try database.rosterMemberIDs(matchingPrefixes: words, conversationID: chatID)
        }
        guard !candidates.isEmpty, limit > 0 else { return [] }

        let recency = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let exactUsername = words.count == 1 ? words[0] : nil

        let ranked = try database.rosterEntries(conversationID: chatID, userIDs: candidates)
            .compactMap { entry -> (Rank, RosterEntry, UserID)? in
                guard let userID = entry.member.userID, userID != selfUserID else { return nil }
                let username = entry.member.username.map { RosterSearchText.normalize($0.value) }
                let rank: Rank
                if let position = recency[userID] {
                    rank = .recentSpeaker(position)
                } else if let exactUsername, username == exactUsername {
                    rank = .exactUsername
                } else {
                    rank = .alphabetical
                }
                return (rank, entry, userID)
            }
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1.sortKey != rhs.1.sortKey {
                    return lhs.1.sortKey.unicodeScalars.lexicographicallyPrecedes(rhs.1.sortKey.unicodeScalars)
                }
                return lhs.2.uuidString.lowercased() < rhs.2.uuidString.lowercased()
            }

        return ranked.prefix(limit).map { MemberMatch(member: $0.1.member, id: $0.2) }
    }

    private enum Rank: Comparable {
        case recentSpeaker(Int)
        case exactUsername
        case alphabetical
    }
}
