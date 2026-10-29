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
    /// True when the user's own reaction is boosted, so a tap must not remove it.
    public let selfBoosted: Bool

    public init(emoji: String, count: UInt64, selfReacted: Bool, pending: Bool, boost: ReactionBoost? = nil, selfBoosted: Bool = false) {
        self.emoji = emoji
        self.count = count
        self.selfReacted = selfReacted
        self.pending = pending
        self.boost = boost
        self.selfBoosted = selfBoosted
    }

    /// The pill with its boost restated for display; see ``ReactionBoost/displayed``.
    public func restatingBoost(_ restate: (FiatAmount) -> FiatAmount) -> ReactionPill {
        guard let boost else { return self }
        return ReactionPill(
            emoji: emoji,
            count: count,
            selfReacted: selfReacted,
            pending: pending,
            boost: ReactionBoost(total: boost.total, displayed: restate(boost.usd)),
            selfBoosted: selfBoosted
        )
    }
}

/// The paid boost on a pill.
public struct ReactionBoost: Hashable, Sendable, Codable {
    /// The total paid, in USD cents.
    public let total: UInt64
    /// The total as the viewer reads it, in the display currency; `nil` shows ``usd``.
    public let displayed: FiatAmount?

    public init(total: UInt64, displayed: FiatAmount? = nil) {
        self.total = total
        self.displayed = displayed
    }

    /// The total paid as a USD amount.
    public var usd: FiatAmount {
        .usd(Decimal(total) / 100)
    }

    /// Converts a server USD amount to whole cents, the only unit boosts are held in.
    public static func cents(usd: Double) -> UInt64 {
        guard usd.isFinite, usd > 0 else { return 0 }
        return UInt64((usd * 100).rounded())
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
    /// A remove was refused because the caller boosted the reaction, which is permanent.
    case cannotRemoveBoosted

    /// The error to show the user for this failure, or nil when the rollback is silent.
    public var userError: ReactionError? {
        switch self {
        case .network, .denied:
            return .reactionFailed
        case .tooManyReactionTypes:
            return .tooManyReactionTypes
        case .messageNotFound, .cannotReact, .cannotRemoveBoosted:
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
