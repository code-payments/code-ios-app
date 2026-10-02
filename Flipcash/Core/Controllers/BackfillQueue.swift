//
//  BackfillQueue.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// The transcript fetches still waiting to run, in the order workers take them. A chat the user
/// opens fetches for itself and drops out of the queue, which puts it ahead of everything waiting.
struct BackfillQueue: Sendable {

    /// What a conversation needs to bring its local transcript level with the server.
    enum Kind: Equatable, Sendable {
        /// The local cursor lags the server's head: stream the missed window from it.
        case delta
        /// Nothing is cached at all: fetch the newest page, which also seats the cursor to head.
        case newestPage
    }

    struct Item: Equatable, Sendable {
        let conversationID: ConversationID
        let kind: Kind
    }

    private var items: [Item] = []
    private var workers = 0

    var count: Int { items.count }

    func contains(_ conversationID: ConversationID) -> Bool {
        items.contains { $0.conversationID == conversationID }
    }

    /// Appends `newItems`, skipping any conversation already queued.
    mutating func enqueue(_ newItems: [Item]) {
        for item in newItems where !contains(item.conversationID) {
            items.append(item)
        }
    }

    /// Drops a queued conversation, for a caller that is fetching it itself. Returns false when it isn't queued.
    @discardableResult
    mutating func remove(_ conversationID: ConversationID) -> Bool {
        guard let index = items.firstIndex(where: { $0.conversationID == conversationID }) else { return false }
        items.remove(at: index)
        return true
    }

    /// Removes and returns the next item to run.
    mutating func popNext() -> Item? {
        items.isEmpty ? nil : items.removeFirst()
    }

    /// Takes the worker slots a caller may start to drain the queue, up to `limit` running at once.
    /// Each started worker calls ``releaseWorker()`` when it finishes.
    mutating func claimWorkers(limit: Int) -> Int {
        let claimed = max(0, min(limit - workers, items.count))
        workers += claimed
        return claimed
    }

    mutating func releaseWorker() {
        workers -= 1
    }
}
