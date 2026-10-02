//
//  FeedReconcile.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// How long the launch reconcile waits before it applies what has landed.
struct FeedReconcileTiming: Sendable {
    /// The longest the reconcile waits for the slowest of the three feeds.
    var feedCap: Duration
    /// The longest it then waits for unread counts to resolve.
    var unreadCap: Duration

    /// Matches the Android launch sync.
    static let launch = FeedReconcileTiming(feedCap: .seconds(2), unreadCap: .milliseconds(1500))
}

/// Waits for a fixed number of units of work to finish, or for a deadline, whichever comes first.
/// The work itself is never cancelled by the deadline: it keeps running and reports late through
/// ``isClosed``.
@MainActor
final class BoundedWait {

    private var remaining: Int
    private var isDone = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var deadline: Task<Void, Never>?

    /// Whether ``wait(upTo:)`` has already returned, so a unit finishing now is late.
    private(set) var isClosed = false

    init(expecting count: Int) {
        remaining = count
        isDone = count <= 0
    }

    /// Records one unit finished.
    func signal() {
        remaining -= 1
        if remaining <= 0 { finish() }
    }

    /// Suspends until every unit has signalled or `cap` has passed, then closes the wait.
    func wait(upTo cap: Duration) async {
        if !isDone {
            deadline = Task { [weak self] in
                try? await Task.sleep(for: cap)
                guard !Task.isCancelled else { return }
                self?.finish()
            }
            await withCheckedContinuation { waiter = $0 }
        }
        deadline?.cancel()
        deadline = nil
        isClosed = true
    }

    private func finish() {
        isDone = true
        waiter?.resume()
        waiter = nil
    }
}

/// The three feeds' results as they land, with the wait for them. A feed that failed settles
/// without a result.
@MainActor
final class FeedArrivals {

    enum Source: Hashable, Sendable {
        case dm(ConversationType)
        case groups
    }

    private var feeds: [Source: [Conversation]] = [:]
    private let wait: BoundedWait

    init(expecting count: Int) {
        wait = BoundedWait(expecting: count)
    }

    /// Whether ``wait(upTo:)`` has returned, so a feed landing now is late.
    var isClosed: Bool { wait.isClosed }

    /// Records a feed's result, `nil` when it failed.
    func arrive(_ source: Source, _ feed: [Conversation]?) {
        if let feed { feeds[source] = feed }
        wait.signal()
    }

    /// The feeds that landed once all have settled or `cap` has passed.
    func wait(upTo cap: Duration) async -> [Source: [Conversation]] {
        await wait.wait(upTo: cap)
        return feeds
    }
}
