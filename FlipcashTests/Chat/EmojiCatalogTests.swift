//
//  EmojiCatalogTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashUI

@Suite("Emoji catalog")
struct EmojiCatalogTests {

    @Test("The bundled catalog decodes every entry with its categories in display order")
    func decodesBundledFile() async throws {
        let catalog = try await EmojiCatalog().load()

        #expect(catalog.emoji.count == 3944)
        #expect(catalog.categories == [
            "Smileys & People", "Animals & Nature", "Food & Drink", "Travel & Places",
            "Activities", "Objects", "Symbols", "Flags",
        ])
        #expect(catalog.emoji.first?.emoji == "😀")
        #expect(Set(catalog.emoji.map(\.category)).isSubset(of: Set(catalog.categories)))
    }

    @Test("Only emoji from 13.0 on are probed, and the answer is kept per OS build")
    func cachesPerBuild() async throws {
        let suite = "undrawable-\(UUID())"
        let entries = [
            try entry("😀", version: "1.0"),
            try entry("🫠", version: "14.0"),
            try entry("🫩", version: "16.0"),
        ]
        let probed = Probed()

        let first = UndrawableEmojiCache(suiteName: suite, osBuild: "A") { emoji in
            probed.append(emoji)
            return emoji != "🫩"
        }
        #expect(await first.undrawable(in: entries) == ["🫩"])
        #expect(probed.values.sorted() == ["🫠", "🫩"].sorted())

        let sameBuild = UndrawableEmojiCache(suiteName: suite, osBuild: "A") { _ in
            Issue.record("a stored answer must not be probed again"); return true
        }
        #expect(await sameBuild.undrawable(in: entries) == ["🫩"])

        let newBuild = UndrawableEmojiCache(suiteName: suite, osBuild: "B") { _ in true }
        #expect(await newBuild.undrawable(in: entries).isEmpty)
    }

    private func entry(_ emoji: String, version: String) throws -> EmojiCatalogEntry {
        let json = #"{"emoji":"\#(emoji)","name":"x","category":"Smileys & People","version":"\#(version)","skinTone":false,"keywords":[]}"#
        return try JSONDecoder().decode(EmojiCatalogEntry.self, from: Data(json.utf8))
    }
}

private final class Probed: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] { lock.withLock { _values } }
    func append(_ value: String) { lock.withLock { _values.append(value) } }
}
