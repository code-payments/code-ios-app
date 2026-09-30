//
//  RosterSearchTextTests.swift
//  FlipcashCoreTests
//

import Testing
import Foundation
@testable import FlipcashCore

/// The text rules roster search indexes by. Android runs the same cases, so a change here is a
/// cross-platform change.
@Suite("Roster search text normalization")
struct RosterSearchTextTests {

    @Test("Lowercases and strips diacritics", arguments: [
        ("Érica", "erica"),
        ("JOSÉ", "jose"),
        ("Zoë", "zoe"),
        ("Ångström", "angstrom"),
        ("Nguyễn", "nguyen"),
    ])
    func stripsDiacritics(input: String, expected: String) {
        #expect(RosterSearchText.normalize(input) == expected)
    }

    @Test("Compatibility forms fold to their plain letters")
    func foldsCompatibilityForms() {
        #expect(RosterSearchText.normalize("Ｅｒｉｃａ") == "erica")
        #expect(RosterSearchText.normalize("ﬁona") == "fiona")
    }

    @Test("Tokens are each display name word plus the username")
    func tokens() {
        let tokens = RosterSearchText.tokens(displayName: "  Érica  de la Cruz ", username: "ecruz")
        #expect(tokens == ["erica", "de", "la", "cruz", "ecruz"])
    }

    @Test("A no-break space splits words like a space")
    func noBreakSpaceSplits() {
        #expect(RosterSearchText.words("Ana\u{00A0}Lima") == ["ana", "lima"])
    }

    @Test("A query drops a leading @ of either width")
    func queryDropsAt() {
        #expect(RosterSearchText.queryWords("@Eri") == ["eri"])
        #expect(RosterSearchText.queryWords("＠eri") == ["eri"])
        #expect(RosterSearchText.queryWords("@") == [])
        #expect(RosterSearchText.queryWords("") == [])
    }

    @Test("The prefix bound sorts above a name continued by an emoji")
    func prefixBoundCoversAstralCharacters() {
        let prefix = "bob"
        let token = RosterSearchText.normalize("Bob🔥")
        #expect(token >= prefix)
        // SQLite compares UTF-8 bytes, so compare the encodings rather than Swift strings.
        #expect(Array(token.utf8).lexicographicallyPrecedes(Array(RosterSearchText.prefixUpperBound(prefix).utf8)))
    }
}
