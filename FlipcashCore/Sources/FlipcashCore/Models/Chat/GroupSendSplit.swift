//
//  GroupSendSplit.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How a group send's total divides between its recipients, in the currency's minor unit.
///
/// Mirrors `test-vectors/group-send-split.json`: each share is the total divided by the share count,
/// rounded down, and the leftover units go one each to the first recipients in selection order, so
/// the shares add up to the total exactly. When the sender includes themselves, their share comes
/// last, never takes a leftover unit, and is kept rather than paid.
public struct GroupSendSplit: Hashable, Sendable {

    /// The most shares one group send can split into, the sender's own included.
    public static let maxRecipients = 10

    /// The smallest part the server accepts, in minor units.
    public static let minimumPartUnits: UInt64 = 1

    /// Why a total cannot be split.
    public enum Rejection: Error, Hashable, Sendable {
        /// No recipients were selected.
        case noRecipients
        /// More than `maxRecipients` shares were selected.
        case tooManyRecipients
        /// A share would be below `minimumPartUnits`.
        case partBelowMinimum
    }

    /// Each paid recipient's part, in minor units, in selection order.
    public let parts: [UInt64]

    /// The sender's own share, kept rather than paid, or nil when the sender isn't included.
    public let kept: UInt64?

    /// What the intent pays: the sum of `parts`.
    public var sent: UInt64 { parts.reduce(0, +) }

    /// Every share, the sender's last.
    private var shares: [UInt64] { parts + (kept.map { [$0] } ?? []) }

    /// How many ways the total is split, the sender's share included.
    public var shareCount: Int { shares.count }

    /// Whether every share, the sender's included, is the same.
    public var isEven: Bool { shares.min() == shares.max() }

    /// The smallest share, which the "~$X Each" label shows when the split is uneven.
    public var smallestPart: UInt64 { shares.min() ?? 0 }

    /// Splits `totalUnits` between `recipients` members, and the sender too when `includesSender`.
    public static func split(totalUnits: UInt64, recipients: Int, includesSender: Bool = false) throws(Rejection) -> GroupSendSplit {
        guard recipients > 0 else { throw .noRecipients }
        let shareCount = recipients + (includesSender ? 1 : 0)
        guard shareCount <= maxRecipients else { throw .tooManyRecipients }

        let count = UInt64(shareCount)
        let base = totalUnits / count
        guard base >= minimumPartUnits else { throw .partBelowMinimum }

        let leftover = Int(totalUnits % count)
        let shares = (0..<shareCount).map { index in index < leftover ? base + 1 : base }
        return GroupSendSplit(parts: Array(shares.prefix(recipients)), kept: includesSender ? shares.last : nil)
    }
}

// MARK: - Fiat -

extension GroupSendSplit {

    /// Splits an entered `total` between `recipients` members, and the sender too when
    /// `includesSender`, in `total.currency`'s minor unit.
    public static func split(total: FiatAmount, recipients: Int, includesSender: Bool = false) throws(Rejection) -> GroupSendSplit {
        try split(totalUnits: minorUnits(of: total), recipients: recipients, includesSender: includesSender)
    }

    /// Each paid part as an amount in `currency`, in selection order.
    public func amounts(in currency: CurrencyCode) -> [FiatAmount] {
        parts.map { Self.amount(units: $0, in: currency) }
    }

    /// What the intent pays, as an amount in `currency`.
    public func sentAmount(in currency: CurrencyCode) -> FiatAmount {
        Self.amount(units: sent, in: currency)
    }

    /// The per-person line: "$1.00 Each" when even, "~$0.33 Each" (the smallest share) when not.
    public func eachLabel(in currency: CurrencyCode) -> String {
        let smallest = Self.amount(units: smallestPart, in: currency).formatted()
        return isEven ? "\(smallest) Each" : "~\(smallest) Each"
    }

    /// `amount` in whole minor units, the fraction beyond the currency's precision dropped.
    static func minorUnits(of amount: FiatAmount) -> UInt64 {
        guard amount.value > 0 else { return 0 }
        let scaled = amount.value * pow(10, amount.currency.maximumFractionDigits) as NSDecimalNumber
        let handler = NSDecimalNumberHandler(roundingMode: .down, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return scaled.rounding(accordingToBehavior: handler).uint64Value
    }

    static func amount(units: UInt64, in currency: CurrencyCode) -> FiatAmount {
        FiatAmount(value: Decimal(units) / pow(10, currency.maximumFractionDigits), currency: currency)
    }
}
