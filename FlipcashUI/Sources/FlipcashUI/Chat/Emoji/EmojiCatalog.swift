//
//  EmojiCatalog.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// One emoji the picker can offer.
nonisolated public struct EmojiCatalogEntry: Decodable, Hashable, Sendable {
    public let emoji: String
    public let name: String
    /// One of the catalog's `categories`.
    public let category: String
    /// The Unicode emoji version that introduced it, as the file writes it ("0.6" … "17.0").
    public let version: String
    public let skinTone: Bool
    public let keywords: [String]

    public init(emoji: String, name: String, category: String, version: String, skinTone: Bool, keywords: [String]) {
        self.emoji = emoji
        self.name = name
        self.category = category
        self.version = version
        self.skinTone = skinTone
        self.keywords = keywords
    }
}

/// The synced emoji list, in display order, with its categories in display order.
nonisolated public struct EmojiCatalogContents: Sendable {
    public let categories: [String]
    public let emoji: [EmojiCatalogEntry]

    public init(categories: [String], emoji: [EmojiCatalogEntry]) {
        self.categories = categories
        self.emoji = emoji
    }
}

/// Loads the bundled `emoji_catalog.json` off the main thread, once.
///
/// The file is several thousand entries; decoding it on the main thread would hitch the first
/// picker presentation.
public actor EmojiCatalog {

    public static let shared = EmojiCatalog()

    public enum CatalogError: Error {
        case missingResource
    }

    private struct File: Decodable {
        let categories: [String]
        let emoji: [EmojiCatalogEntry]
    }

    private var contents: EmojiCatalogContents?

    public init() {}

    /// The catalog, decoded on first call and kept for the rest of the process.
    public func load() throws -> EmojiCatalogContents {
        if let contents { return contents }
        guard let url = Bundle.module.url(forResource: "emoji_catalog", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let contents = EmojiCatalogContents(categories: file.categories, emoji: file.emoji)
        self.contents = contents
        return contents
    }
}

/// The emoji this OS build cannot draw, probed once per build and kept in `UserDefaults`.
///
/// Only emoji from Unicode 13.0 on are probed: nothing older failed on any OS the app supports.
public actor UndrawableEmojiCache {

    public static let shared = UndrawableEmojiCache()

    /// The oldest emoji version that needs probing.
    static let probedFromVersion = 13.0

    private let defaults: UserDefaults
    private let key: String
    private let isDrawable: @Sendable (String) -> Bool
    private var undrawable: Set<String>?

    /// `osBuild` scopes the stored answer: an OS update adds glyphs, so it has to be probed again.
    /// A nil `suiteName` stores it in the standard defaults.
    public init(
        suiteName: String? = nil,
        osBuild: String = ProcessInfo.processInfo.operatingSystemVersionString,
        isDrawable: @escaping @Sendable (String) -> Bool = EmojiDrawability.isDrawable
    ) {
        self.defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.key = "flipcash-undrawable-emoji-\(osBuild)"
        self.isDrawable = isDrawable
    }

    /// The catalog emoji this OS cannot draw.
    public func undrawable(in entries: [EmojiCatalogEntry]) -> Set<String> {
        if let undrawable { return undrawable }
        if let stored = defaults.stringArray(forKey: key) {
            let set = Set(stored)
            undrawable = set
            return set
        }
        let set = Set(
            entries
                .filter { (Double($0.version) ?? .infinity) >= Self.probedFromVersion }
                .map(\.emoji)
                .filter { !isDrawable($0) }
        )
        defaults.set(set.sorted(), forKey: key)
        undrawable = set
        return set
    }
}
