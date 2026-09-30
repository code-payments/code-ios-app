//
//  RosterSearchText.swift
//  FlipcashCore
//

import Foundation

/// The text rules roster search indexes and queries by. Android applies the same rules, so a query
/// matches the same members on both platforms.
public enum RosterSearchText {

    /// Returns `text` lowercased, NFKD-decomposed, and stripped of every combining mark
    /// (general category `M`: `Mn`, `Mc`, `Me`), so "Érica" and "erica" compare equal.
    public static func normalize(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where !isMark(scalar) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Returns the normalized words of `text`, split on runs of Unicode `White_Space`, empty words dropped.
    public static func words(_ text: String) -> [String] {
        normalize(text)
            .unicodeScalars
            .split(whereSeparator: \.properties.isWhitespace)
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Returns the distinct search tokens for a member: each word of the display name, plus the
    /// username without its `@`.
    public static func tokens(displayName: String, username: String?) -> Set<String> {
        var tokens = Set(words(displayName))
        if let username {
            tokens.formUnion(words(username))
        }
        return tokens
    }

    /// Returns the words of a typed query, with a leading `@` (either width) dropped from each word.
    public static func queryWords(_ query: String) -> [String] {
        // NFKD folds the fullwidth "＠" to "@", so one check covers both.
        words(query)
            .map { $0.hasPrefix("@") ? String($0.drop(while: { $0 == "@" })) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Returns the exclusive upper bound of a prefix range, so `token >= prefix AND token < bound`
    /// matches every token starting with `prefix`.
    ///
    /// U+10FFFF rather than U+FFFF: SQLite compares UTF-8 bytes, and a token whose next character is
    /// outside the BMP (an emoji after a name, say) sorts above `prefix + U+FFFF`.
    public static func prefixUpperBound(_ prefix: String) -> String {
        prefix + "\u{10FFFF}"
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }
}
