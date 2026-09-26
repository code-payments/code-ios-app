//
//  ReactionStrip.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The emoji the long-press strip offers, before the trailing "+" the UI adds.
public enum ReactionStrip {

    /// One emoji in the strip.
    public struct Entry: Hashable, Sendable {
        public let emoji: String
        /// True when the user has reacted to the message with this emoji.
        public let highlighted: Bool

        public init(emoji: String, highlighted: Bool) {
            self.emoji = emoji
            self.highlighted = highlighted
        }
    }

    /// Returns the recents in rank order, highlighting the ones the user reacted with, followed by
    /// the user's other reactions, newest first.
    public static func entries(recents: [String], selfReactions: [SelfReaction]) -> [Entry] {
        let mine = Set(selfReactions.map(\.emoji))
        let recentSet = Set(recents)
        // Enumerated so equal times keep their input order, as the reference's stable sort does.
        let extra = selfReactions.enumerated()
            .sorted { lhs, rhs in
                lhs.element.reactedAt != rhs.element.reactedAt
                    ? lhs.element.reactedAt > rhs.element.reactedAt
                    : lhs.offset < rhs.offset
            }
            .map(\.element.emoji)
            .filter { !recentSet.contains($0) }
        return recents.map { Entry(emoji: $0, highlighted: mine.contains($0)) }
            + extra.map { Entry(emoji: $0, highlighted: true) }
    }
}
