//
//  EmojiPickerModel.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The picker's pure grouping logic — search, category sections, the Frequently Used row, and the
/// undrawable filter — kept apart from the SwiftUI sheet so it's testable without loading the real
/// catalog or standing up a view.
public enum EmojiPickerModel {

    /// One section the grid draws, in order.
    public struct Section: Identifiable, Hashable {
        public let id: String
        public let title: String
        public let entries: [EmojiCatalogEntry]

        public init(id: String, title: String, entries: [EmojiCatalogEntry]) {
            self.id = id
            self.title = title
            self.entries = entries
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
    /// `undrawable` is filtered out of every section, including the Frequently Used row — a recent
    /// pick that this OS build can no longer render is worth dropping silently rather than showing a
    /// tofu box for.
    public static func sections(
        catalog: EmojiCatalogContents,
        undrawable: Set<String>,
        recents: [String],
        query: String
    ) -> [Section] {
        let drawable = catalog.emoji.filter { !undrawable.contains($0.emoji) }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.isEmpty else {
            let needle = trimmedQuery.lowercased()
            let matches = drawable.filter { entry in
                entry.name.lowercased().contains(needle)
                    || entry.keywords.contains { $0.lowercased().contains(needle) }
            }
            return [Section(id: searchResultsID, title: "Search Results", entries: matches)]
        }

        var sections: [Section] = []
        if !recents.isEmpty {
            let byEmoji = Dictionary(uniqueKeysWithValues: drawable.map { ($0.emoji, $0) })
            var seen = Set<String>()
            let frequent = recents.compactMap { emoji -> EmojiCatalogEntry? in
                guard seen.insert(emoji).inserted else { return nil }
                return byEmoji[emoji]
            }
            if !frequent.isEmpty {
                sections.append(Section(id: frequentlyUsedID, title: frequentlyUsedTitle, entries: frequent))
            }
        }
        for category in catalog.categories {
            let entries = drawable.filter { $0.category == category }
            guard !entries.isEmpty else { continue }
            sections.append(Section(id: category, title: category, entries: entries))
        }
        return sections
    }
}
