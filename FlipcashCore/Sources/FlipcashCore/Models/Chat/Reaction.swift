//
//  Reaction.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One emoji's displayed reaction on a message, with `count` and `selfReacted` already resolved
/// from the pending tap over the confirmed server state.
public struct ReactionPill: Hashable, Sendable, Codable, Identifiable {
    public var id: String { emoji }

    public let emoji: String
    public let count: UInt64
    public let selfReacted: Bool
    /// True while the user's last tap on this emoji has not been reconciled with the server.
    public let pending: Bool
    public let boost: ReactionBoost?

    public init(emoji: String, count: UInt64, selfReacted: Bool, pending: Bool, boost: ReactionBoost? = nil) {
        self.emoji = emoji
        self.count = count
        self.selfReacted = selfReacted
        self.pending = pending
        self.boost = boost
    }
}

/// The paid boost on a pill, a phase-2 seam that nothing creates in phase 1.
public struct ReactionBoost: Hashable, Sendable, Codable {
    public let total: UInt64

    public init(total: UInt64) {
        self.total = total
    }
}

/// An add or remove the caller must send to the server for one emoji.
public struct ReactionCall: Hashable, Sendable {

    /// The direction of a reaction call.
    public enum Op: Hashable, Sendable {
        case add
        case remove
    }

    public let op: Op
    public let emoji: String

    public init(op: Op, emoji: String) {
        self.op = op
        self.emoji = emoji
    }
}

/// Why an add or remove call failed, as far as the reaction merge needs to know.
public enum ReactionFailure: Hashable, Sendable {
    case network
    case denied
    case messageNotFound
    case cannotReact
    case tooManyReactionTypes

    /// The error to show the user for this failure, or nil when the rollback is silent.
    public var userError: ReactionError? {
        switch self {
        case .network, .denied:
            return .reactionFailed
        case .tooManyReactionTypes:
            return .tooManyReactionTypes
        case .messageNotFound, .cannotReact:
            return nil
        }
    }
}

/// A reaction failure the user is told about.
public enum ReactionError: Error, Hashable, Sendable {
    case reactionFailed
    case tooManyReactionTypes
}

/// The outcome of an add or remove call.
public enum ReactionResult: Hashable, Sendable {
    case ok(count: UInt64, selfReacted: Bool, version: UInt64, selfReactedAt: Date?)
    case failed(ReactionFailure)
}

/// An emoji the user's displayed state has them reacting with, and when they reacted.
public struct SelfReaction: Hashable, Sendable, Codable {
    public let emoji: String
    public let reactedAt: Date

    public init(emoji: String, reactedAt: Date) {
        self.emoji = emoji
        self.reactedAt = reactedAt
    }
}
