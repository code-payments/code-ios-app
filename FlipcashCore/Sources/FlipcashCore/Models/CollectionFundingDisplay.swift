//
//  CollectionFundingDisplay.swift
//  FlipcashCore
//

import Foundation

/// How a collection payment's conversion fee reads, decided on the fee's micros before anything is
/// rounded for display.
public enum CollectionFundingFeeKind: Equatable, Sendable {

    /// Nothing converts, so no fee line is drawn.
    case none

    /// A conversion that costs nothing.
    case zero

    /// Above zero but under half a minor unit, too small to round to one.
    case underMinorUnit

    /// A whole number of minor units.
    case exact(minorUnits: Int64)

    /// Any other fee, rounded half-up to the minor unit.
    case approximate(minorUnits: Int64)

    /// The kind of a fee of `feeMicros`, where `conversion` says whether any leg converts.
    public init(feeMicros: Int64, conversion: Bool, minorDigits: Int) {
        guard conversion else {
            self = .none
            return
        }
        let unit = microsPerMinorUnit(minorDigits: minorDigits)
        if feeMicros == 0 {
            self = .zero
        } else if 2 * feeMicros < unit {
            self = .underMinorUnit
        } else if feeMicros % unit == 0 {
            self = .exact(minorUnits: feeMicros / unit)
        } else {
            self = .approximate(minorUnits: roundedMinorUnits(feeMicros, minorDigits: minorDigits))
        }
    }
}

/// The en-US strings the collection payment modal and its Payment Details sheet draw for a funding
/// plan.
///
/// Every amount is rounded to the minor unit on integer micros, half-up, before it is formatted, so
/// the formatter is never left a tie to break. Fees are summed on micros and rounded once, and so is
/// the total, which can differ by a minor unit from the rows rounded one by one.
public struct CollectionFundingDisplay: Equatable, Sendable {

    /// A labelled amount, with any lines drawn under it.
    public struct Row: Equatable, Sendable {
        public let label: String
        public let amount: String
        public let sublabels: [String]

        public init(label: String, amount: String, sublabels: [String] = []) {
            self.label = label
            self.amount = amount
            self.sublabels = sublabels
        }
    }

    /// How far short the balances fall, as "You’re $1.00 Short"; `nil` when no top-up is needed.
    public let shortBy: String?

    /// The button that tops up and pays, as "Add $5.00 and Pay $10.00"; `nil` when no top-up is
    /// needed.
    public let addButton: String?

    /// The top-up amount; `nil` when no top-up is needed.
    public let topUp: String?

    /// The modal's fee line; `nil` when nothing converts.
    public let modalFee: String?

    /// "You’ll Pay": the paying currency and the amount.
    public let pay: Row

    /// The id of the currency in ``pay``.
    public let payCurrency: String

    /// "You’ll Use": a row per leg, the paying currency first, then Dollars, then the others by
    /// amount sold, largest first and ties by id.
    public let use: [Row]

    /// The id of the currency each ``use`` row sells, in the same order.
    public let useCurrencies: [String]

    /// The sum of the amounts sold, rounded once.
    public let total: Row

    /// What a Dollars leg is called when the wallet holds no Dollars to take a name from.
    public static let dollarsName = "Dollars"

    /// The label on the total row.
    public static let totalLabel = "Total"

    /// The strings for `plan`, whose amounts are in `currency`.
    ///
    /// - Parameters:
    ///   - dollars: the id of the Dollars currency.
    ///   - names: each currency's name by id; a currency missing from it is called by its id, and
    ///     Dollars by ``dollarsName``.
    public init(plan: CollectionFundingPlan, currency: CurrencyCode, dollars: String, names: [String: String]) {
        func name(_ id: String) -> String {
            names[id] ?? (id == dollars ? Self.dollarsName : id)
        }
        func money(_ micros: Int64) -> String {
            Self.amountText(micros: micros, currency: currency)
        }

        let paying = plan.payingCurrency
        let payingLegs = plan.legs.filter { $0.source == paying }
        let dollarsLegs = plan.legs.filter { $0.source == dollars && $0.source != paying }
        let otherLegs = plan.legs
            .filter { $0.source != paying && $0.source != dollars }
            .sorted { lhs, rhs in
                lhs.soldMicros != rhs.soldMicros ? lhs.soldMicros > rhs.soldMicros : lhs.source < rhs.source
            }

        let orderedLegs = payingLegs + dollarsLegs + otherLegs
        self.useCurrencies = orderedLegs.map(\.source)
        self.use = orderedLegs.map { leg in
            var sublabels: [String] = []
            if leg.source == dollars, let split = leg.dollarsSplit, split.fromTopUpMicros > 0 {
                if split.fromBalanceMicros > 0 {
                    sublabels.append("\(money(split.fromBalanceMicros)) from balance")
                }
                sublabels.append("\(money(split.fromTopUpMicros)) from Apple Pay")
            } else if let fee = Self.feeSublabel(feeMicros: leg.feeMicros, conversion: leg.conversion, currency: currency) {
                sublabels.append(fee)
            }
            return Row(label: name(leg.source), amount: money(leg.soldMicros), sublabels: sublabels)
        }

        if plan.topUpMicros > 0 {
            let digits = currency.maximumFractionDigits
            let shortMinorUnits = ceilMicros(plan.shortfallMicros, toMinorDigits: digits) / microsPerMinorUnit(minorDigits: digits)
            self.shortBy = "You’re \(Self.moneyText(minorUnits: shortMinorUnits, currency: currency)) Short"
            self.addButton = "Add \(money(plan.topUpMicros)) and Pay \(money(plan.amountMicros))"
            self.topUp = money(plan.topUpMicros)
        } else {
            self.shortBy = nil
            self.addButton = nil
            self.topUp = nil
        }

        self.modalFee = Self.modalFee(
            feeMicros: plan.totalFeeMicros,
            conversion: plan.legs.contains { $0.conversion },
            currency: currency
        )
        self.pay = Row(label: name(paying), amount: money(plan.amountMicros))
        self.payCurrency = paying
        self.total = Row(
            label: Self.totalLabel,
            amount: money(plan.legs.reduce(0) { $0 + $1.soldMicros })
        )
    }

    // MARK: - Fees -

    /// The modal's fee line for a total fee of `feeMicros`: "no conversion fees", or "plus ~$0.02 of
    /// conversion fees"; `nil` when nothing converts.
    public static func modalFee(feeMicros: Int64, conversion: Bool, currency: CurrencyCode) -> String? {
        let kind = CollectionFundingFeeKind(feeMicros: feeMicros, conversion: conversion, minorDigits: currency.maximumFractionDigits)
        if kind == .zero {
            return "no conversion fees"
        }
        return feeText(kind, currency: currency).map { "plus \($0) of conversion fees" }
    }

    /// The line under a leg in Payment Details for a fee of `feeMicros`, as "~$0.02 conversion fee";
    /// `nil` when the leg doesn't convert or converts at no fee.
    public static func feeSublabel(feeMicros: Int64, conversion: Bool, currency: CurrencyCode) -> String? {
        let kind = CollectionFundingFeeKind(feeMicros: feeMicros, conversion: conversion, minorDigits: currency.maximumFractionDigits)
        return feeText(kind, currency: currency).map { "\($0) conversion fee" }
    }

    /// The fee as drawn, as "<$0.01", "$0.04" or "~$0.02"; `nil` when there is no fee to draw.
    private static func feeText(_ kind: CollectionFundingFeeKind, currency: CurrencyCode) -> String? {
        switch kind {
        case .none, .zero:
            return nil
        case .underMinorUnit:
            return "<\(moneyText(minorUnits: 1, currency: currency))"
        case .exact(let minorUnits):
            return moneyText(minorUnits: minorUnits, currency: currency)
        case .approximate(let minorUnits):
            return "~\(moneyText(minorUnits: minorUnits, currency: currency))"
        }
    }

    // MARK: - Amounts -

    /// `micros` rounded half-up to the minor unit and formatted, as "$1,234.57".
    public static func amountText(micros: Int64, currency: CurrencyCode) -> String {
        moneyText(minorUnits: roundedMinorUnits(micros, minorDigits: currency.maximumFractionDigits), currency: currency)
    }

    /// An exact count of minor units, formatted. Handing the formatter whole minor units leaves it
    /// nothing to round.
    private static func moneyText(minorUnits: Int64, currency: CurrencyCode) -> String {
        let value = Decimal(sign: .plus, exponent: -currency.maximumFractionDigits, significand: Decimal(minorUnits))
        return FiatAmount(value: value, currency: currency).formatted()
    }
}

/// `micros` rounded half-up to a whole number of minor units.
func roundedMinorUnits(_ micros: Int64, minorDigits: Int) -> Int64 {
    let unit = microsPerMinorUnit(minorDigits: minorDigits)
    let (quotient, remainder) = micros.quotientAndRemainder(dividingBy: unit)
    return quotient + (2 * remainder >= unit ? 1 : 0)
}
