//
//  RosterSearchText.swift
//  FlipcashCore
//

import Foundation

/// The text rules roster search indexes and queries by. Android applies the same rules, so a query
/// matches the same members on both platforms.
public enum RosterSearchText {

    /// Returns `text` NFKD-decomposed, lowercased, and stripped of nonspacing marks (general category
    /// `Mn`), so "Érica" and "erica" compare equal. Lowercasing after NFKD folds "İ" to "i" plus a
    /// combining dot, which the strip then drops. Spacing marks (`Mc`) are kept: in scripts such as
    /// Devanagari they carry the vowel.
    public static func normalize(_ text: String) -> String {
        let folded = text.decomposedStringWithCompatibilityMapping.lowercased()
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Returns the normalized words of `text`, split on Unicode `White_Space` and separators
    /// (general category `Z`), empty words dropped.
    public static func words(_ text: String) -> [String] {
        normalize(text)
            .unicodeScalars
            .split(whereSeparator: isSeparator)
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Returns the distinct search tokens for a member: each word of the display name, plus the
    /// username without its `@`.
    public static func tokens(displayName: String, username: String?) -> Set<String> {
        var tokens = Set(words(displayName))
        if let username {
            tokens.formUnion(words(username).map(droppingAt).filter { !$0.isEmpty })
        }
        return tokens
    }

    /// Returns the words of a typed query, with a leading `@` (either width) dropped from each word.
    public static func queryWords(_ query: String) -> [String] {
        words(query).map(droppingAt).filter { !$0.isEmpty }
    }

    /// Returns the exclusive upper bound of a prefix range, so `token >= prefix AND token < bound`
    /// matches every token starting with `prefix`.
    ///
    /// U+10FFFF rather than U+FFFF: SQLite compares UTF-8 bytes, and a token whose next character is
    /// outside the BMP (an emoji after a name, say) sorts above `prefix + U+FFFF`.
    public static func prefixUpperBound(_ prefix: String) -> String {
        prefix + "\u{10FFFF}"
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
