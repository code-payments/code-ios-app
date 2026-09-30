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

    @Test("Dotted capital I folds to a plain i")
    func dottedCapitalI() {
        #expect(RosterSearchText.normalize("İstanbul") == "istanbul")
    }

    @Test("Spacing marks are kept, so Devanagari vowels survive")
    func keepsSpacingMarks() {
        // U+093F DEVANAGARI VOWEL SIGN I is category Mc.
        #expect(RosterSearchText.normalize("कि") == "कि")
    }

    @Test("Tokens are each display name word plus the username")
    func tokens() {
        let tokens = RosterSearchText.tokens(displayName: "  Érica  de la Cruz ", username: "ecruz")
        #expect(tokens == ["erica", "de", "la", "cruz", "ecruz"])
        #expect(RosterSearchText.tokens(displayName: "Bo", username: "＠bo_b") == ["bo", "bo_b"])
    }

    @Test("Any whitespace or separator splits words", arguments: ["\u{00A0}", "\u{2028}", "\u{3000}", "\t"])
    func separatorsSplit(separator: String) {
        #expect(RosterSearchText.words("Ana\(separator)Lima") == ["ana", "lima"])
    }

    @Test("A query drops a leading @ of either width")
    func queryDropsAt() {
        #expect(RosterSearchText.queryWords("@Eri") == ["eri"])
        #expect(RosterSearchText.queryWords("＠eri") == ["eri"])
        #expect(RosterSearchText.queryWords("@") == [])
        #expect(RosterSearchText.queryWords("@@eri") == ["@eri"])
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
