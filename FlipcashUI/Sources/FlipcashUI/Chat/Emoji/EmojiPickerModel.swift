//
//  EmojiPickerModel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The picker's pure grouping logic — search, category sections, the Frequently Used row, skin-tone
/// families, and the undrawable filter — kept apart from the SwiftUI sheet so it's testable without
/// loading the real catalog or standing up a view.
nonisolated public enum EmojiPickerModel {

    /// One section the grid draws, in order.
    public struct Section: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let entries: [EmojiCatalogEntry]

        public init(id: String, title: String, entries: [EmojiCatalogEntry]) {
            self.id = id
            self.title = title
            self.entries = entries
        }
    }

    /// The catalog's drawable entries, split into base emoji and their skin-tone families, with a
    /// lowercased search text per base. Built once per catalog load, off the main thread.
    public struct Index: Sendable {

        /// The catalog's categories, in display order.
        public let categories: [String]
        /// The drawable emoji without a skin tone, in catalog order — the only ones the grid shows.
        public let bases: [EmojiCatalogEntry]

        // Parallel to `bases`: the name and keywords, lowercased once, so a search is a substring
        // scan rather than lowercasing every keyword on every keystroke.
        private let searchText: [String]
        private let tones: [String: [EmojiCatalogEntry]]
        private let baseOfVariant: [String: String]
        private let byEmoji: [String: EmojiCatalogEntry]

        /// Indexes `catalog` with `undrawable` removed everywhere.
        public init(catalog: EmojiCatalogContents, undrawable: Set<String>) {
            let all = catalog.emoji
            let basesByStripped = Dictionary(
                all.filter { !$0.skinTone }.map { (Self.strippingTones($0.emoji), $0.emoji) },
                uniquingKeysWith: { first, _ in first }
            )
            let basesByName = Dictionary(
                all.filter { !$0.skinTone }.map { ($0.name, $0.emoji) },
                uniquingKeysWith: { first, _ in first }
            )

            var bases: [EmojiCatalogEntry] = []
            var tones: [String: [EmojiCatalogEntry]] = [:]
            var baseOfVariant: [String: String] = [:]
            var byEmoji: [String: EmojiCatalogEntry] = [:]
            var precedingBase: String?
            for entry in all {
                guard entry.skinTone else {
                    precedingBase = entry.emoji
                    if !undrawable.contains(entry.emoji) {
                        bases.append(entry)
                        byEmoji[entry.emoji] = entry
                    }
                    continue
                }
                // Most variants are their base plus modifiers. The two-person forms (🫱🏻‍🫲🏼 for 🤝,
                // 🧑🏻‍🐰‍🧑🏼 for 👯) aren't, so fall back to the name, then to the catalog's own
                // ordering, which always lists a family straight after its base.
                let base = basesByStripped[Self.strippingTones(entry.emoji)]
                    ?? basesByName[Self.strippingTones(fromName: entry.name)]
                    ?? precedingBase
                guard let base, !undrawable.contains(entry.emoji) else { continue }
                tones[base, default: []].append(entry)
                baseOfVariant[entry.emoji] = base
                byEmoji[entry.emoji] = entry
            }

            self.categories = catalog.categories
            self.bases = bases
            self.searchText = bases.map { entry in
                ([entry.name] + entry.keywords).joined(separator: "\u{1F}").lowercased()
            }
            self.tones = tones
            self.baseOfVariant = baseOfVariant
            self.byEmoji = byEmoji
        }

        /// The entry for `emoji`, base or variant, if it's in the catalog and drawable.
        public func entry(for emoji: String) -> EmojiCatalogEntry? {
            byEmoji[emoji]
        }

        /// The tone family `emoji` belongs to — its base first, then each drawable variant in
        /// catalog order — or empty when it has no drawable variants.
        public func toneFamily(of emoji: String) -> [EmojiCatalogEntry] {
            let base = baseOfVariant[emoji] ?? emoji
            guard let variants = tones[base], !variants.isEmpty, let baseEntry = byEmoji[base] else { return [] }
            return [baseEntry] + variants
        }

        /// The bases whose name or a keyword contains `needle`, which must already be lowercased.
        func bases(matching needle: String) -> [EmojiCatalogEntry] {
            zip(bases, searchText).compactMap { entry, text in text.contains(needle) ? entry : nil }
        }

        private static func strippingTones(_ emoji: String) -> String {
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: emoji.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0xFE0F })
            return String(scalars)
        }

        private static func strippingTones(fromName name: String) -> String {
            name.replacing(/(: |, )(light|medium-light|medium|medium-dark|dark) skin tone/, with: "")
        }
    }

    /// The id `sections` gives the Frequently Used row, so the category bar can skip past it.
    public static let frequentlyUsedID = "frequently-used"
    public static let frequentlyUsedTitle = "Frequently Used"
    /// The id `sections` gives the single section a non-empty search produces.
    public static let searchResultsID = "search-results"

    /// Builds the sections the grid draws.
    ///
    /// - With an empty `query`: a Frequently Used row (`recents`, deduped and capped to
    ///   `RecentReactionsStore.pickerRowLimit` by the caller — this takes whatever it's handed)
    ///   followed by one section per catalog category, in catalog order.
    /// - With a non-empty `query`: a single "search results" section, catalog order, matched
    ///   case-insensitively against an entry's name or keywords — no Frequently Used row, since a
    ///   search is the user looking for something specific rather than reaching for the recent set.
    ///
    /// Categories and search results hold base emoji only; a skin tone is picked from the base's
    /// `Index.toneFamily(of:)`. The Frequently Used row keeps a recent tone as it was sent.
    ///
    /// `undrawable` is filtered out of every section, including the Frequently Used row — a recent
    /// pick that this OS build can no longer render is worth dropping silently rather than showing a
    /// tofu box for.
    public static func sections(index: Index, recents: [String], query: String) -> [Section] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty else {
            let matches = index.bases(matching: trimmedQuery.lowercased())
            return [Section(id: searchResultsID, title: "Search Results", entries: matches)]
        }

        var sections: [Section] = []
        var seen = Set<String>()
        let frequent = recents.compactMap { emoji -> EmojiCatalogEntry? in
            guard seen.insert(emoji).inserted else { return nil }
            return index.entry(for: emoji)
        }
        if !frequent.isEmpty {
            sections.append(Section(id: frequentlyUsedID, title: frequentlyUsedTitle, entries: frequent))
        }
        let byCategory = Dictionary(grouping: index.bases, by: \.category)
        for category in index.categories {
            guard let entries = byCategory[category], !entries.isEmpty else { continue }
            sections.append(Section(id: category, title: category, entries: entries))
        }
        return sections
    }
}
