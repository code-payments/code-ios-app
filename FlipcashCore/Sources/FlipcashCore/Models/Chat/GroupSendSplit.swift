//
//  GroupSendSplit.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// How a group send's total divides between its recipients, in the currency's minor unit.
///
/// Mirrors `test-vectors/group-send-split.json`: each part is the total divided by the recipient
/// count, rounded down, and the leftover units go one each to the first recipients in selection
/// order, so the parts add up to the total exactly.
public struct GroupSendSplit: Hashable, Sendable {

    /// The most members one group send can pay.
    public static let maxRecipients = 10

    /// The smallest part the server accepts, in minor units.
    public static let minimumPartUnits: UInt64 = 1

    /// Why a total cannot be split.
    public enum Rejection: Error, Hashable, Sendable {
        /// No recipients were selected.
        case noRecipients
        /// More than `maxRecipients` were selected.
        case tooManyRecipients
        /// A part would be below `minimumPartUnits`.
        case partBelowMinimum
    }

    /// Each paid recipient's part, in minor units, in selection order.
    public let parts: [UInt64]

    /// The sender's own part when they shared the total, which stays with them and is not paid.
    public let youPart: UInt64?

    init(parts: [UInt64], youPart: UInt64? = nil) {
        self.parts = parts
        self.youPart = youPart
    }

    /// Whether every recipient gets the same part.
    public var isEven: Bool { parts.min() == parts.max() }

    /// The smallest part, which the "~$X Each" label shows when the split is uneven.
    public var smallestPart: UInt64 { parts.min() ?? 0 }

    /// Splits `totalUnits` between `recipients` members, or between `youAt`'s position and the members
    /// when the sender shares the total: the split is then `recipients + 1` ways and `parts` leaves
    /// out the sender's, which `youPart` keeps. `maxRecipients` caps the paid members, not the sender.
    public static func split(
        totalUnits: UInt64,
        recipients: Int,
        youAt: Int? = nil,
        maxRecipients: Int = GroupSendSplit.maxRecipients
    ) throws(Rejection) -> GroupSendSplit {
        guard recipients > 0 else { throw .noRecipients }
        guard recipients <= maxRecipients else { throw .tooManyRecipients }

        let people = recipients + (youAt == nil ? 0 : 1)
        let count = UInt64(people)
        let base = totalUnits / count
        guard base >= minimumPartUnits else { throw .partBelowMinimum }

        let leftover = Int(totalUnits % count)
        var parts = (0..<people).map { index in index < leftover ? base + 1 : base }
        guard let youAt else { return GroupSendSplit(parts: parts, youPart: nil) }
        let youPart = parts.remove(at: youAt)
        return GroupSendSplit(parts: parts, youPart: youPart)
    }
}

// MARK: - Fiat -

extension GroupSendSplit {

    /// Splits an entered `total` between `recipients` members, in `total.currency`'s minor unit.
    public static func split(
        total: FiatAmount,
        recipients: Int,
        youAt: Int? = nil,
        maxRecipients: Int = GroupSendSplit.maxRecipients
    ) throws(Rejection) -> GroupSendSplit {
        try split(totalUnits: minorUnits(of: total), recipients: recipients, youAt: youAt, maxRecipients: maxRecipients)
    }

    /// Each part as an amount in `currency`, in selection order.
    public func amounts(in currency: CurrencyCode) -> [FiatAmount] {
        parts.map { Self.amount(units: $0, in: currency) }
    }

    /// The per-person line: "$1.00 Each" when even, "~$0.33 Each" (the smallest part) when not.
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
