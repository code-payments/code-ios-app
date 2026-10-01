//
//  ServerMentionSearch.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.mention-search")

/// Answers mention searches from the pool `Chat.GetMentionSuggestions` returns.
///
/// The pool is fetched once per composing session, when the picker first opens in a visit, then held
/// and filtered locally as the user types: a suggestion matches when every word of the query is a
/// prefix of one of its ``MentionSearchText`` tokens, and matches keep the server's order. A new
/// message moves its sender to the front of the held pool; a sender the pool doesn't hold is not
/// added, since only the server decides who is suggested.
///
/// A chat whose pool can't be fetched, or that the server answers `DENIED` or `NOT_FOUND`, matches
/// nobody; the user can still type a handle by hand.
final class ServerMentionSearch: RosterSearchSource {

    private let fetching: any MentionSuggestionFetching
    private let owner: KeyPair
    private let blockedUserIDs: () -> Set<UserID>
    /// Writes fetched profiles into the local cache so their names and avatars resolve elsewhere.
    private let cache: @Sendable (Profile, UserID) throws -> Void

    private var pools: [ConversationID: Pool] = [:]

    private enum Pool {
        /// A fetch in flight, keyed so a superseded fetch can't overwrite a newer one when it lands.
        case loading(UUID, Task<[MentionSuggestion]?, Never>)
        case ready([MentionSuggestion])
        /// The fetch failed; searches match nobody until the next ``prepare(chatID:)``.
        case unavailable
    }

    init(
        fetching: any MentionSuggestionFetching,
        owner: KeyPair,
        blockedUserIDs: @escaping () -> Set<UserID> = { [] },
        cache: @escaping @Sendable (Profile, UserID) throws -> Void = { _, _ in }
    ) {
        self.fetching = fetching
        self.owner = owner
        self.blockedUserIDs = blockedUserIDs
        self.cache = cache
    }

    func prepare(chatID: ConversationID) async -> Bool {
        let task: Task<[MentionSuggestion]?, Never>
        if case .loading(_, let inFlight) = pools[chatID] {
            task = inFlight
        } else {
            task = load(chatID)
        }
        return await task.value != nil
    }

    func search(chatID: ConversationID, query: String, limit: Int) async throws -> [MemberMatch] {
        let pool: [MentionSuggestion]?
        switch pools[chatID] {
        case .ready(let held):
            pool = held
        case .loading(_, let task):
            pool = await task.value
        case .unavailable:
            pool = nil
        case nil:
            // A search that beats `prepare` starts the session's fetch, which `prepare` then joins.
            pool = await load(chatID).value
        }
        guard let pool else { return [] }
        return Self.filter(pool, query: query, limit: limit, blocked: blockedUserIDs())
    }

    /// Moves each new message's sender to the front of that chat's held pool, when the message is
    /// newer than the last one the pool knows they sent.
    func apply(_ event: ConversationStreamEvent) {
        guard case .chatEvents(let chatID, let events) = event, case .ready(var pool) = pools[chatID] else { return }
        var moved = false
        for mutation in events.flatMap(\.mutations) {
            switch mutation {
            case .sent(let message):
                guard
                    let senderID = message.senderID,
                    let index = pool.firstIndex(where: { $0.userID == senderID })
                else { continue }
                let suggestion = pool[index]
                if let lastSentAt = suggestion.lastSentAt, lastSentAt >= message.date { continue }
                pool.remove(at: index)
                pool.insert(MentionSuggestion(userID: senderID, profile: suggestion.profile, lastSentAt: message.date), at: 0)
                moved = true
            case .edited, .deleted:
                continue
            }
        }
        if moved { pools[chatID] = .ready(pool) }
    }

    /// The suggestions in `pool` matching `query`, in pool order; an empty query matches everyone.
    static func filter(_ pool: [MentionSuggestion], query: String, limit: Int, blocked: Set<UserID>) -> [MemberMatch] {
        let words = MentionSearchText.queryWords(query)
        return pool.lazy
            .filter { !blocked.contains($0.userID) }
            .filter { suggestion in
                let tokens = MentionSearchText.tokens(
                    displayName: suggestion.profile.displayName ?? "",
                    username: suggestion.profile.username?.value
                )
                return words.allSatisfy { word in tokens.contains { $0.hasPrefix(word) } }
            }
            .prefix(max(limit, 0))
            .map { MemberMatch(member: $0.member, id: $0.userID) }
    }

    private func load(_ chatID: ConversationID) -> Task<[MentionSuggestion]?, Never> {
        let token = UUID()
        let task = Task { [weak self, fetching, owner, cache] () -> [MentionSuggestion]? in
            let pool: [MentionSuggestion]?
            do {
                let fetched = try await fetching.getMentionSuggestions(owner: owner, conversationID: chatID)
                Task.detached {
                    for suggestion in fetched {
                        do {
                            try cache(suggestion.profile, suggestion.userID)
                        } catch {
                            logger.warning("Failed to cache a mention suggestion's profile", metadata: ["error": "\(error)"])
                        }
                    }
                }
                pool = fetched
            } catch {
                logger.info("Mention suggestions unavailable", metadata: [
                    "conversationID": "\(chatID)",
                    "error": "\(error)",
                ])
                pool = nil
            }
            self?.settle(chatID, token: token, pool: pool)
            return pool
        }
        pools[chatID] = .loading(token, task)
        return task
    }

    private func settle(_ chatID: ConversationID, token: UUID, pool: [MentionSuggestion]?) {
        guard case .loading(let current, _) = pools[chatID], current == token else { return }
        pools[chatID] = pool.map(Pool.ready) ?? .unavailable
    }
}
