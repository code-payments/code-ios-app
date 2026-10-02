//
//  MentionSearchText.swift
//  Flipcash
//

import Foundation

/// The text rules mention search matches by. Android applies the same rules, so a query matches the
/// same members on both platforms.
nonisolated enum MentionSearchText {

    /// Returns `text` NFKD-decomposed, lowercased, and stripped of nonspacing marks (general category
    /// `Mn`), so "Érica" and "erica" compare equal. Lowercasing after NFKD folds "İ" to "i" plus a
    /// combining dot, which the strip then drops. Spacing marks (`Mc`) are kept: in scripts such as
    /// Devanagari they carry the vowel.
    static func normalize(_ text: String) -> String {
        let folded = text.decomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Returns the normalized words of `text`, split on Unicode `White_Space` and separators
    /// (general category `Z`), empty words dropped.
    static func words(_ text: String) -> [String] {
        normalize(text)
            .unicodeScalars
            .split(whereSeparator: isSeparator)
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Returns the distinct search tokens for a member: each word of the display name, plus the
    /// username without its `@`.
    static func tokens(displayName: String, username: String?) -> Set<String> {
        var tokens = Set(words(displayName))
        if let username {
            tokens.formUnion(words(username).map(droppingAt).filter { !$0.isEmpty })
        }
        return tokens
    }

    /// Returns the words of a typed query, with a leading `@` (either width) dropped from each word.
    static func queryWords(_ query: String) -> [String] {
        words(query).map(droppingAt).filter { !$0.isEmpty }
    }

    // NFKD folds the fullwidth "＠" to "@", so one check covers both.
    private static func droppingAt(_ word: String) -> String {
        word.hasPrefix("@") ? String(word.dropFirst()) : word
    }

    private static func isSeparator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return scalar.properties.isWhitespace
        }
    }
}
