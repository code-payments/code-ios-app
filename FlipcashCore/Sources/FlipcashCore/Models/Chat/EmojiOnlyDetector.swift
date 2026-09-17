//
//  EmojiOnlyDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Whether a message body is nothing but a handful of emoji — the transcript draws one of those
/// bare and enlarged instead of in a bubble. Pure and synchronous, like `LinkDetector`.
public enum EmojiOnlyDetector {

    /// True when `text` is 1...`limit` emoji and nothing else. Whitespace around and between them is
    /// ignored, so "👍 👍" qualifies.
    public static func isEmojiOnly(_ text: String, limit: Int = 3) -> Bool {
        var count = 0
        for cluster in text {
            if cluster.isWhitespace { continue }
            guard isEmojiCluster(cluster) else { return false }
            count += 1
            // Bail on the one past the limit rather than walking a long message to its end.
            if count > limit { return false }
        }
        return count > 0
    }

    /// One grapheme cluster that renders as an emoji.
    ///
    /// `isEmoji` alone is too broad — `1`, `#` and `*` all carry it, each being the base of a keycap
    /// sequence, and a bare `unicodeScalars.count > 1` test would admit a letter with a combining
    /// mark. What separates a real emoji is default emoji presentation, an explicit U+FE0F variation
    /// selector, or the keycap combining mark itself (`#⃣` is U+0023 U+20E3 and carries no U+FE0F).
    /// The second clause is load-bearing beyond keycaps: a ZWJ sequence whose base has only text
    /// presentation — `🏳️‍🌈`, `❤️‍🔥` — fails the first test and qualifies only because Swift keeps
    /// the U+FE0F on the composed `Character`. Skin-tone modifiers, regional-indicator flags, and a
    /// ZWJ sequence built on an already-emoji-presentation base (`👨‍👩‍👧‍👦`) pass on the first test.
    private static func isEmojiCluster(_ cluster: Character) -> Bool {
        guard let first = cluster.unicodeScalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation
            || cluster.unicodeScalars.contains { $0 == "\u{FE0F}" || $0 == "\u{20E3}" }
    }
}
