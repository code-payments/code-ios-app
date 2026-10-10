//
//  MentionDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One `@handle` found in a message: where it is, and whose handle it names.
public struct DetectedMention: Hashable, Sendable, Codable {

    /// UTF-16 offsets into the message text, covering the `@` and the handle.
    public let location: Int
    public let length: Int
    public let username: Username

    public var range: NSRange { NSRange(location: location, length: length) }

    public init(range: NSRange, username: Username) {
        self.location = range.location
        self.length = range.length
        self.username = username
    }
}

/// Finds the well-formed `@handle`s in a chat message. Pure and synchronous: whether the handle
/// belongs to anyone is only known once it is tapped.
public enum MentionDetector {

    /// Every `@handle` in `text` that does not overlap one of `links`, in the order they appear.
    ///
    /// The character before the `@` must not be a handle character, `.` or `@`, so an email
    /// address or `@@name` is not a mention. One `_` may sit between that character and the `@`, so
    /// `_@jeff_` is an italic mention; see the trim below. The handle ends at the first character a handle
    /// cannot hold, and a handle running straight into more handle characters or another `@`
    /// is dropped rather than cut short.
    public static func mentions(in text: String, excluding links: [DetectedLink]) -> [DetectedMention] {
        guard text.contains("@") else { return [] }

        return text.matches(of: pattern).compactMap { match -> DetectedMention? in
            let (_, opener, mention, handle) = match.output
            var name = String(handle)
            var end = mention.endIndex
            // `_@jeff_`: the `_` before the `@` opened an italic, so the handle's last `_` closes it
            // and is not the handle's. Only while two handle characters remain, and only when an
            // opening `_` was there: `_hey @jeff_` keeps the handle it wrote.
            if !opener.isEmpty, name.hasSuffix("_"), name.count > 2 {
                name.removeLast()
                end = text.index(before: end)
            }
            guard let username = Username(name.lowercased()) else { return nil }

            let range = NSRange(mention.startIndex..<end, in: text)
            guard !links.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else {
                return nil
            }
            return DetectedMention(range: range, username: username)
        }
    }

    // Swift Regex has no lookbehind, so the preceding character is matched (and excluded from
    // the mention's range) instead. Case folds after the match; `Username` stores lowercase.
    private nonisolated(unsafe) static let pattern = /(?:^|[^A-Za-z0-9_.@])(_?)(@([A-Za-z0-9_]{2,15}))(?![A-Za-z0-9_@])/
}
