//
//  ChatSearchRecents.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.chat-search-recents")

/// The chats the signed-in user opened from Chats Search, newest first, for the search screen's
/// Recent row.
///
/// Owner-scoped in `UserDefaults` like ``RecentReactionsStore``, and read at init, so the row is
/// ready the moment the screen opens.
@MainActor
@Observable
final class ChatSearchRecents {

    /// How many chats the row keeps.
    nonisolated static let limit = 10

    private(set) var conversationIDs: [ConversationID]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    /// Loads the owner's recents. Unreadable data is treated as none.
    init(defaults: UserDefaults = .standard, owner: PublicKey) {
        self.defaults = defaults
        self.key = "flipcash-\(owner.base58)-chat-search-recents"
        let stored = defaults.array(forKey: key) as? [Data] ?? []
        self.conversationIDs = stored.map(ConversationID.init(data:))
    }

    /// Moves `conversationID` to the front, dropping the oldest past ``limit``.
    func record(_ conversationID: ConversationID) {
        conversationIDs = Self.recording(conversationID, in: conversationIDs)
        defaults.set(conversationIDs.map(\.data), forKey: key)
        logger.debug("Recorded chat search recent", metadata: ["count": "\(conversationIDs.count)"])
    }

    nonisolated static func recording(_ conversationID: ConversationID, in ids: [ConversationID]) -> [ConversationID] {
        Array(([conversationID] + ids.filter { $0 != conversationID }).prefix(limit))
    }
}

/// The currencies `Discover` last returned, popular then new, kept so Chats Search can filter them
/// without opening a stream per keystroke.
@MainActor
@Observable
final class DiscoveredCurrencies {

    private(set) var mints: [MintMetadata] = []

    @ObservationIgnored private let discover: (DiscoverCategory) -> AsyncThrowingStream<[MintMetadata], Error>
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(discover: @escaping (DiscoverCategory) -> AsyncThrowingStream<[MintMetadata], Error>) {
        self.discover = discover
    }

    /// Takes the first snapshot of each category and closes the streams. A refresh already in
    /// flight is reused.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task {
            async let popular = firstBatch(.popular)
            async let new = firstBatch(.new)
            let batches = await [popular, new]
            let fetched = batches.flatMap { $0 }
            if !fetched.isEmpty {
                mints = fetched
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func firstBatch(_ category: DiscoverCategory) async -> [MintMetadata] {
        do {
            for try await batch in discover(category) {
                return batch
            }
        } catch {
            logger.warning("Discover failed for chat search", metadata: ["category": "\(category)", "error": "\(error)"])
        }
        return []
    }
}
