//
//  ChatQuote.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The quoted original shown above a reply's body — display-ready, like everything else a chat row
/// draws. The transcript mapper resolves the replied-to id into one of these; the panel that draws
/// it knows nothing about the database or which messages happen to be loaded.
public struct ChatQuote: Hashable, Sendable, Codable {

    /// What the original was, which selects the panel's presentation.
    public enum Kind: Hashable, Sendable, Codable {
        case text
        /// A payment. The snippet is the formatted amount.
        case cash
        /// The original is not in the local database, or it has been deleted. The panel renders
        /// the placeholder copy and the row is not tappable.
        case unavailable
    }

    /// The transcript row to jump to, or `nil` when there is nothing to jump to.
    public let stableID: String?
    /// "You" for the viewer's own message, the counterpart's display name otherwise. Empty for an
    /// unavailable original, whose author is not known.
    public let authorName: String
    public let snippet: String
    public let kind: Kind

    public init(stableID: String?, authorName: String, snippet: String, kind: Kind) {
        self.stableID = stableID
        self.authorName = authorName
        self.snippet = snippet
        self.kind = kind
    }

    /// Whether tapping the panel goes anywhere.
    public var isJumpable: Bool { stableID != nil }

    /// Copy for an original the client cannot show.
    public static let unavailableSnippet = "Original message unavailable"

    /// Copy for an original that has since been deleted.
    public static let deletedSnippet = "This message was deleted"

    /// Longest snippet the panel renders. Past this the panel would wrap to a third line and the
    /// bubble would grow around a preview rather than the message.
    public static let snippetLimit = 120

    /// One line of preview text: newlines collapsed to spaces, truncated at ``snippetLimit``.
    public static func snippet(forText text: String) -> String {
        let flattened = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > snippetLimit else { return flattened }
        return flattened.prefix(snippetLimit) + "…"
    }
}
