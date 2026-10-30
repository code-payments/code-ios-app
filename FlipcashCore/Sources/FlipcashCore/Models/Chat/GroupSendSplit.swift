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

    /// The most people one group send can split between, You included.
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

    /// Splits `totalUnits` between `recipients` members, or between the members and the sender when
    /// `includesYou`: the split is then `recipients + 1` ways, You's part is always the last one, and
    /// `parts` leaves it out while `youPart` keeps it. The cap counts You.
    public static func split(totalUnits: UInt64, recipients: Int, includesYou: Bool = false) throws(Rejection) -> GroupSendSplit {
        guard recipients > 0 else { throw .noRecipients }
        let people = recipients + (includesYou ? 1 : 0)
        guard people <= maxRecipients else { throw .tooManyRecipients }

        let count = UInt64(people)
        let base = totalUnits / count
        guard base >= minimumPartUnits else { throw .partBelowMinimum }

        let leftover = Int(totalUnits % count)
        var parts = (0..<people).map { index in index < leftover ? base + 1 : base }
        let youPart = includesYou ? parts.removeLast() : nil
        return GroupSendSplit(parts: parts, youPart: youPart)
    }
}

// MARK: - Fiat -

extension GroupSendSplit {

    /// Splits an entered `total` between `recipients` members, in `total.currency`'s minor unit.
    public static func split(total: FiatAmount, recipients: Int, includesYou: Bool = false) throws(Rejection) -> GroupSendSplit {
        try split(totalUnits: minorUnits(of: total), recipients: recipients, includesYou: includesYou)
    }

    /// Each part as an amount in `currency`, in selection order.
    public func amounts(in currency: CurrencyCode) -> [FiatAmount] {
        parts.map { Self.amount(units: $0, in: currency) }
    }

    /// The per-person line: "$1.00 Each" when even, "~$0.33 Each" (the smallest part paid) when not.
    /// When the sender shares the total it ends ", including You", and is even only if the sender's part
    /// equals the others'.
    public func eachLabel(in currency: CurrencyCode) -> String {
        let smallest = Self.amount(units: smallestPart, in: currency).formatted()
        let allEqual = isEven && (youPart.map { $0 == parts.first } ?? true)
        let label = allEqual ? "\(smallest) Each" : "~\(smallest) Each"
        return youPart == nil ? label : "\(label), including You"
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
