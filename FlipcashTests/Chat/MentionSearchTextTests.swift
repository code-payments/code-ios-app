//
//  MentionSearchTextTests.swift
//  FlipcashTests
//

import Testing
import Foundation
@testable import Flipcash

/// The text rules mention search matches by. Android runs the same cases, so a change here is a
/// cross-platform change.
@Suite("Mention search text normalization")
struct MentionSearchTextTests {

    @Test("Lowercases and strips diacritics", arguments: [
        ("Érica", "erica"),
        ("JOSÉ", "jose"),
        ("Zoë", "zoe"),
        ("Ångström", "angstrom"),
        ("Nguyễn", "nguyen"),
    ])
    func stripsDiacritics(input: String, expected: String) {
        #expect(MentionSearchText.normalize(input) == expected)
    }

    @Test("Compatibility forms fold to their plain letters")
    func foldsCompatibilityForms() {
        #expect(MentionSearchText.normalize("Ｅｒｉｃａ") == "erica")
        #expect(MentionSearchText.normalize("ﬁona") == "fiona")
    }

    @Test("Dotted capital I folds to a plain i")
    func dottedCapitalI() {
        #expect(MentionSearchText.normalize("İstanbul") == "istanbul")
    }

    @Test("Spacing marks are kept, so Devanagari vowels survive")
    func keepsSpacingMarks() {
        // U+093F DEVANAGARI VOWEL SIGN I is category Mc.
        #expect(MentionSearchText.normalize("कि") == "कि")
    }

    @Test("Tokens are each display name word plus the username")
    func tokens() {
        let tokens = MentionSearchText.tokens(displayName: "  Érica  de la Cruz ", username: "ecruz")
        #expect(tokens == ["erica", "de", "la", "cruz", "ecruz"])
        #expect(MentionSearchText.tokens(displayName: "Bo", username: "＠bo_b") == ["bo", "bo_b"])
    }

    @Test("Any whitespace or separator splits words", arguments: ["\u{00A0}", "\u{2028}", "\u{3000}", "\t"])
    func separatorsSplit(separator: String) {
        #expect(MentionSearchText.words("Ana\(separator)Lima") == ["ana", "lima"])
    }

    @Test("A query drops a leading @ of either width")
    func queryDropsAt() {
        #expect(MentionSearchText.queryWords("@Eri") == ["eri"])
        #expect(MentionSearchText.queryWords("＠eri") == ["eri"])
        #expect(MentionSearchText.queryWords("@") == [])
        #expect(MentionSearchText.queryWords("@@eri") == ["@eri"])
        #expect(MentionSearchText.queryWords("") == [])
    }
}
