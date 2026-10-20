//
//  ReactionBoostSplit.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Who a reaction boost pays and how much each payee gets, in whole USD cents.
///
/// Mirrors `test-vectors/reaction-boost-split.json`: a member boosting another member's message
/// pays the group creator 20% of the whole, rounded half-even to the cent, and the message's sender
/// the rest. When the creator pays, or wrote the message, the one other party is paid the whole.
public enum ReactionBoostSplit: Hashable, Sendable {

    /// One payment to the message's sender, or to the creator when they wrote it.
    case single(Share)
    /// Two payments in one intent, listed sender then creator.
    case multi(sender: Share, creator: Share)

    /// The creator's percentage of a two-payee boost.
    public static let creatorPercent: UInt64 = 20

    /// The smallest share the server accepts, in cents.
    public static let minimumShareCents: UInt64 = 1

    /// The smallest total that splits into two shares of at least `minimumShareCents`.
    public static let minimumTwoPayeeCents: UInt64 = 3

    /// Who a share is paid to.
    public enum Role: Hashable, Sendable {
        case creator
        case sender
    }

    /// One payee's role, user, and amount in cents.
    public struct Share: Hashable, Sendable {
        public let role: Role
        public let userID: UserID
        public let cents: UInt64

        public init(role: Role, userID: UserID, cents: UInt64) {
            self.role = role
            self.userID = userID
            self.cents = cents
        }
    }

    /// Why a boost cannot be paid.
    public enum Rejection: Error, Hashable, Sendable {
        /// The payer wrote the message.
        case selfBoost
        /// A share would be below `minimumShareCents`.
        case shareBelowMinimum
    }

    /// The shares in payment order.
    public var shares: [Share] {
        switch self {
        case .single(let share):
            return [share]
        case .multi(let sender, let creator):
            return [sender, creator]
        }
    }

    /// The smallest total, in cents, this payer can boost this message with; nil for a self-boost.
    public static func minimumCents(payer: UserID, messageSender: UserID, creator: UserID) -> UInt64? {
        guard payer != messageSender else { return nil }
        return isTwoPayee(payer: payer, messageSender: messageSender, creator: creator) ? minimumTwoPayeeCents : minimumShareCents
    }

    /// Splits `totalCents` paid by `payer` for a message `messageSender` wrote in a group `creator` owns.
    public static func split(totalCents: UInt64, payer: UserID, messageSender: UserID, creator: UserID) throws(Rejection) -> ReactionBoostSplit {
        guard payer != messageSender else { throw .selfBoost }

        guard isTwoPayee(payer: payer, messageSender: messageSender, creator: creator) else {
            guard totalCents >= minimumShareCents else { throw .shareBelowMinimum }
            let role: Role = messageSender == creator ? .creator : .sender
            return .single(Share(role: role, userID: messageSender, cents: totalCents))
        }

        let creatorCents = roundHalfEven(totalCents * creatorPercent, divisor: 100)
        let senderCents = totalCents - creatorCents
        guard creatorCents >= minimumShareCents, senderCents >= minimumShareCents else {
            throw .shareBelowMinimum
        }
        return .multi(
            sender: Share(role: .sender, userID: messageSender, cents: senderCents),
            creator: Share(role: .creator, userID: creator, cents: creatorCents)
        )
    }

    private static func isTwoPayee(payer: UserID, messageSender: UserID, creator: UserID) -> Bool {
        payer != creator && messageSender != creator
    }

    private static func roundHalfEven(_ value: UInt64, divisor: UInt64) -> UInt64 {
        let quotient = value / divisor
        let twiceRemainder = (value % divisor) * 2
        if twiceRemainder > divisor { return quotient + 1 }
        if twiceRemainder < divisor { return quotient }
        return quotient.isMultiple(of: 2) ? quotient : quotient + 1
    }
}
