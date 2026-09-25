//
//  RecentReactionsStore.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.recent-reactions")

/// How often and how recently the signed-in user reacted with each emoji, ranked for the reaction
/// strip and the picker's recents row.
///
/// Owner-scoped in `UserDefaults` the way `ChatDraftStore` scopes its file: one device serves every
/// account, and switching back to one should find its recents where it left them.
@MainActor
@Observable
final class RecentReactionsStore {

    /// How many of the user's most used emoji follow the six fixed defaults in the long-press strip.
    static let stripLimit = 6
    /// How many emoji the long-press strip holds in all, once the catalog fills in after the recents
    /// and the user's own reactions.
    static let stripFillLimit = 12
    /// How many emoji the picker's recents row offers.
    static let pickerRowLimit = 7

    private var stats: [String: RecentReactions.Usage]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    /// Loads the owner's usage. Unreadable data is treated as no usage: the strip falls back to the
    /// defaults, which is what a new account sees anyway.
    init(defaults: UserDefaults = .standard, owner: PublicKey) {
        self.defaults = defaults
        self.key = "flipcash-\(owner.base58)-reaction-recents"
        if let data = defaults.data(forKey: key),
           let stats = try? JSONDecoder().decode([String: RecentReactions.Usage].self, from: data) {
            self.stats = stats
        } else {
            self.stats = [:]
        }
    }

    /// Counts one reaction the user added with `emoji`.
    func record(_ emoji: String, at date: Date = .now) {
        RecentReactions.record(emoji, at: date, in: &stats)
        do {
            defaults.set(try JSONEncoder().encode(stats), forKey: key)
        } catch {
            logger.error("Failed to encode recent reactions", metadata: ["error": "\(error)"])
        }
    }

    /// Up to `limit` emoji, most used first, padded with the defaults and leaving out `undrawable`.
    func row(limit: Int, undrawable: Set<String> = []) -> [String] {
        RecentReactions.rank(stats: stats, undrawable: undrawable, limit: limit)
    }
}

extension ReactionStrip {

    /// `entries` followed by `catalog` emoji not already in it, up to `limit` in all, so the strip
    /// always has more to scroll under its "+". Never drops one of `entries`.
    nonisolated static func filled(_ entries: [Entry], from catalog: [String], limit: Int) -> [Entry] {
        var seen = Set(entries.map(\.emoji))
        var filled = entries
        for emoji in catalog where filled.count < limit && seen.insert(emoji).inserted {
            filled.append(Entry(emoji: emoji, highlighted: false))
        }
        return filled
    }
}
