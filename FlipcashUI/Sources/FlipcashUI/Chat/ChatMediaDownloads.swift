//
//  ChatMediaDownloads.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The chat photo downloads running in this process, by cache key, so a bubble and the prefetcher
/// that want the same copy share one download instead of fetching it twice.
///
/// Whoever starts a download claims its key first; anyone who finds the key claimed waits for it to
/// end and then looks in the cache. The notification extension runs in its own process and claims
/// nothing here.
@MainActor
final class ChatMediaDownloads {

    /// A download's hold on its key. Only the claim that holds a key can release it.
    struct Claim {
        let key: String
        fileprivate let id: UInt64
    }

    private var holders: [String: UInt64] = [:]
    private var waiters: [String: [() -> Void]] = [:]
    private var lastID: UInt64 = 0

    nonisolated init() {}

    /// Claims `key` for a download about to start, or returns nil when one is already running.
    func claim(_ key: String) -> Claim? {
        guard holders[key] == nil else { return nil }
        lastID += 1
        holders[key] = lastID
        return Claim(key: key, id: lastID)
    }

    /// Ends `claim`'s download, landed or not, and calls everyone waiting on its key. A claim
    /// released already does nothing, so a load that ends late never frees a newer claim on its key.
    func release(_ claim: Claim) {
        guard holders[claim.key] == claim.id else { return }
        holders[claim.key] = nil
        for waiter in waiters.removeValue(forKey: claim.key) ?? [] {
            waiter()
        }
    }

    /// Calls `body` once the download running for `key` ends. Returns false, without keeping
    /// `body`, when none is running.
    func whenFinished(_ key: String, _ body: @escaping () -> Void) -> Bool {
        guard holders[key] != nil else { return false }
        waiters[key, default: []].append(body)
        return true
    }
}
