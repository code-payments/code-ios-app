//
//  ChatGroupCard.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// What the group's card at the head of its transcript shows: the chat's own picture, its title,
/// and the rule it runs on. A group's counterpart is the chat itself, so this is a sibling of
/// ``ChatProfileCard`` rather than a case of it — nothing here relates to the address book, and
/// nothing there states a requirement.
public struct ChatGroupCard: Hashable, Sendable, Codable {

    /// The chat's server-set title.
    public var title: String

    /// Stable identity for the avatar (monogram colour + image cache key) — the conversation id.
    public var avatarID: String

    /// The chat picture's thumbnail bytes; nil renders the BlurHash or the monogram.
    public var imageData: Data?

    /// The chat picture's BlurHash, drawn until the bytes arrive.
    public var blurhash: String?

    /// The chat's stated entry rule, already worded for display, or nil when it states none. The
    /// line is shown whether or not the viewer satisfies it — the design states the requirement to
    /// a member too (node 10125:19256).
    public var requirement: String?

    public init(title: String, avatarID: String, imageData: Data? = nil, blurhash: String? = nil, requirement: String? = nil) {
        self.title = title
        self.avatarID = avatarID
        self.imageData = imageData
        self.blurhash = blurhash
        self.requirement = requirement
    }
}
