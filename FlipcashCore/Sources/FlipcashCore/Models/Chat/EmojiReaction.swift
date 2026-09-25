//
//  EmojiReaction.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

/// One user's reaction with one emoji, as a reactor list or summary lists it.
public struct Reactor: Hashable, Sendable {
    public let userID: UserID
    public let reactedAt: Date?
    /// The emoji aggregate's version when this reactor last toggled; orders a reactor list.
    public let version: UInt64

    public init(userID: UserID, reactedAt: Date?, version: UInt64) {
        self.userID = userID
        self.reactedAt = reactedAt
        self.version = version
    }
}

/// One emoji's aggregate on a message, as the server reports it.
public struct EmojiReaction: Hashable, Sendable {
    public let emoji: String
    public let count: UInt64
    /// The current user's entry, set exactly when they react with this emoji.
    public let selfReactor: Reactor?
    public let sampleReactors: [Reactor]
    public let version: UInt64

    public init(emoji: String, count: UInt64, selfReactor: Reactor?, sampleReactors: [Reactor], version: UInt64) {
        self.emoji = emoji
        self.count = count
        self.selfReactor = selfReactor
        self.sampleReactors = sampleReactors
        self.version = version
    }

    /// The summary entry `ReactionState` accepts.
    public var summaryEntry: ReactionState.SummaryEntry {
        ReactionState.SummaryEntry(
            emoji: emoji,
            count: count,
            selfReacted: selfReactor != nil,
            version: version,
            selfReactedAt: selfReactor?.reactedAt
        )
    }

    /// The successful response `ReactionState.respond` accepts.
    public var result: ReactionResult {
        .ok(count: count, selfReacted: selfReactor != nil, version: version, selfReactedAt: selfReactor?.reactedAt)
    }
}

/// One page of an emoji's reactors, newest first.
public struct ReactorPage: Hashable, Sendable {
    public let reactors: [Reactor]
    /// The token for the next page; nil when there is none.
    public let nextPageToken: Data?
    public let version: UInt64

    public init(reactors: [Reactor], nextPageToken: Data?, version: UInt64) {
        self.reactors = reactors
        self.nextPageToken = nextPageToken
        self.version = version
    }
}

// MARK: - Proto

extension Reactor {
    /// Builds a reactor from its proto, or nil when the user id does not parse.
    public init?(_ proto: Flipcash_Messaging_V1_Reactor) {
        guard let userID = try? UUID(data: proto.userID.value) else { return nil }
        self.init(userID: userID, reactedAt: proto.hasReactedTs ? proto.reactedTs.date : nil, version: proto.version)
    }
}

extension EmojiReaction {
    /// Builds an emoji aggregate from its proto.
    public init(_ proto: Flipcash_Messaging_V1_EmojiReaction) {
        self.init(
            emoji: proto.emoji.value,
            count: proto.count,
            selfReactor: proto.hasSelfReactor ? Reactor(proto.selfReactor) : nil,
            sampleReactors: proto.sampleReactors.compactMap(Reactor.init),
            version: proto.version
        )
    }
}

extension ReactionState {
    /// A state seeded from a message's reaction summary.
    public init(_ summary: Flipcash_Messaging_V1_ReactionSummary) {
        self.init()
        applySummary(summary.reactions.map { EmojiReaction($0).summaryEntry })
    }
}
