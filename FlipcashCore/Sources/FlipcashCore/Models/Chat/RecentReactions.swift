//
//  RecentReactions.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Ranks the emoji the strip and picker offer first, from how often and how recently each was used.
public enum RecentReactions {

    /// The emoji offered before any have been used, in their order.
    public static let defaults = ["❤️", "👍", "😂", "😮", "😢", "🔥"]

    /// How often and how recently one emoji was reacted with.
    public struct Usage: Hashable, Sendable, Codable {
        public var count: Int
        public var lastUsed: Date

        public init(count: Int, lastUsed: Date) {
            self.count = count
            self.lastUsed = lastUsed
        }
    }

    /// Records one use of `emoji` at `date` in `stats`.
    public static func record(_ emoji: String, at date: Date, in stats: inout [String: Usage]) {
        if var usage = stats[emoji] {
            usage.count += 1
            usage.lastUsed = max(usage.lastUsed, date)
            stats[emoji] = usage
        } else {
            stats[emoji] = Usage(count: 1, lastUsed: date)
        }
    }

    /// Returns up to `limit` emoji: the used ones by count descending, then last use descending,
    /// padded with `defaults`, leaving out any in `undrawable`.
    ///
    /// Padding stops at the defaults, so an unused picker asking for more than six gets six.
    public static func rank(stats: [String: Usage], undrawable: Set<String>, limit: Int) -> [String] {
        var ranked = stats
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                if lhs.value.lastUsed != rhs.value.lastUsed { return lhs.value.lastUsed > rhs.value.lastUsed }
                // Only for a dictionary's lack of order; two uses at the same instant do not happen.
                return lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
            }
            .map(\.key)
            .filter { !undrawable.contains($0) }
        for emoji in defaults where !ranked.contains(emoji) && !undrawable.contains(emoji) {
            ranked.append(emoji)
        }
        return Array(ranked.prefix(max(limit, 0)))
    }
}
