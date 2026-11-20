//
//  CollectionFundingPlan.swift
//  FlipcashCore
//

import Foundation

/// One currency a collection payment can draw on, valued in the request currency.
///
/// Every amount in the funding planner is an integer count of fiat micros, 1e-6 of the request
/// currency's major unit, so the planner carries no platform money types and matches Android's
/// `Fiat` to the micro.
public struct CollectionFundingBalance: Equatable, Hashable, Sendable {

    /// The currency's id, unique among the balances handed to the planner.
    public let id: String

    /// The balance's fiat value in the request currency, in micros.
    public let fiatMicros: Int64

    /// The sell fee, in basis points, taken out of an amount sold from this currency.
    public let sellFeeBps: Int64

    public init(id: String, fiatMicros: Int64, sellFeeBps: Int64) {
        self.id = id
        self.fiatMicros = fiatMicros
        self.sellFeeBps = sellFeeBps
    }
}

/// How a collection payment of a fixed amount is funded from the payer's balances, after any
/// top-up those balances can't cover.
public struct CollectionFundingPlan: Equatable, Sendable {

    /// One source's part of the plan.
    public struct Leg: Equatable, Sendable {

        /// The id of the currency the leg draws on.
        public let source: String

        /// Whether the leg converts into the paying currency rather than spending it directly.
        public let conversion: Bool

        /// The amount sold, fee included, in micros.
        public let soldMicros: Int64

        /// The sell fee taken out of `soldMicros`, in micros.
        public let feeMicros: Int64

        /// What the leg delivers into the paying currency, in micros.
        public let deliveredMicros: Int64

        /// How the amount sold divides between the Dollars balance and the top-up; set on the
        /// Dollars leg only.
        public let dollarsSplit: DollarsSplit?
    }

    /// The Dollars leg's amount sold, divided between what was already held and what the top-up
    /// adds. The balance is used before the top-up.
    public struct DollarsSplit: Equatable, Sendable {

        /// The part drawn from the Dollars balance, in micros.
        public let fromBalanceMicros: Int64

        /// The part drawn from the top-up, in micros.
        public let fromTopUpMicros: Int64
    }

    /// The amount the plan pays, in micros.
    public let amountMicros: Int64

    /// The id of the currency the payment is made in.
    public let payingCurrency: String

    /// What the balances can't cover after fees, in micros; zero when the payment needs no top-up.
    public let shortfallMicros: Int64

    /// The Dollars to add before paying, in micros: zero, or at least the minimum top-up.
    public let topUpMicros: Int64

    /// The legs in funding order, describing the plan after any top-up.
    public let legs: [Leg]

    /// Whether the balances cover the payment without a top-up.
    public var payableWithoutTopUp: Bool { shortfallMicros == 0 }

    /// The sum of the legs' fees, in micros.
    public var totalFeeMicros: Int64 { legs.reduce(0) { $0 + $1.feeMicros } }

    /// No balance at or above the dust floor funds the payment: there is a top-up and every leg
    /// takes its Dollars from it (sections 1 and 2), so the Request screen's Pay adds the money
    /// with no sheet. A balance the plan leaves untouched, such as one the minimum top-up made
    /// unnecessary, doesn't count. Matches Android's `CollectionFundingPlan.fundedByTopUpAlone`.
    public var fundedByTopUpAlone: Bool {
        topUpMicros > 0 && legs.allSatisfy { $0.dollarsSplit?.fromBalanceMicros == 0 }
    }
}

/// Input `planCollectionFunding` refuses to plan.
public enum CollectionFundingPlanError: Error, Equatable, Sendable {
    case negativeAmount(Int64)
    case invalidMinorDigits(Int)
    case negativeMinimumTopUp(Int64)
    case negativeBalance(id: String, micros: Int64)
    case duplicateBalance(id: String)
}

/// Plans how a collection payment of `amountMicros` is funded from `balances`.
///
/// The paying currency is `selected`, else `lastPaid`, else `dollars`, whatever its balance. Sources
/// fund in order: the paying currency, then Dollars, then every other currency by balance, smallest
/// first and ties by id, each covering only what is still needed. The paying currency and Dollars
/// spend at full balance; any other currency sells with its fee taken out of the amount sold. A
/// balance worth less than half a minor unit is dust and is dropped before anything else. When
/// the balances fall short, the top-up is the shortfall rounded up to the minor unit, and never
/// below `minimumTopUpMicros`; it is added to Dollars and the legs are planned again.
///
/// Rounding boundary: fees and gross-ups round half-up to the micro, on exact integers, the same
/// figures Android's `launchpadSellFee` and `grossingUpLaunchpadSellFee` give. Legs do not go
/// through `entryAffordableAfterFee`, whose floor to the cent would strand a sub-cent remainder in
/// every drained currency.
///
/// Throws on input Android's `planCollectionFunding` also rejects: a negative amount, top-up minimum
/// or balance, `minorDigits` outside 0...6, or two balances with the same id. A repeated id would
/// otherwise count toward capacity twice while only its first entry funds a leg, so the plan would
/// under-fund the payment.
public func planCollectionFunding(
    amountMicros: Int64,
    minorDigits: Int,
    minimumTopUpMicros: Int64,
    selected: String?,
    lastPaid: String?,
    dollars: String,
    balances: [CollectionFundingBalance]
) throws(CollectionFundingPlanError) -> CollectionFundingPlan {
    guard amountMicros >= 0 else { throw .negativeAmount(amountMicros) }
    guard (0...6).contains(minorDigits) else { throw .invalidMinorDigits(minorDigits) }
    guard minimumTopUpMicros >= 0 else { throw .negativeMinimumTopUp(minimumTopUpMicros) }
    var seen: Set<String> = []
    for balance in balances {
        guard balance.fiatMicros >= 0 else { throw .negativeBalance(id: balance.id, micros: balance.fiatMicros) }
        guard seen.insert(balance.id).inserted else { throw .duplicateBalance(id: balance.id) }
    }

    let paying = selected ?? lastPaid ?? dollars

    // Dust would display as zero and never funds, Dollars and the paying currency included: it
    // adds nothing to capacity, gets no leg, and stays in the wallet.
    let unit = microsPerMinorUnit(minorDigits: minorDigits)
    let balances = balances.filter { !isDust($0.fiatMicros, minorUnitMicros: unit) }

    let capacity = balances.reduce(Int64(0)) { total, balance in
        total + spendableMicros(balance, paying: paying, dollars: dollars)
    }
    let shortfall = max(amountMicros - capacity, 0)

    var funded = balances
    var topUp: Int64 = 0
    if shortfall > 0 {
        topUp = max(ceilMicros(shortfall, toMinorDigits: minorDigits), minimumTopUpMicros)
        if let index = funded.firstIndex(where: { $0.id == dollars }) {
            let held = funded[index]
            funded[index] = CollectionFundingBalance(
                id: held.id,
                fiatMicros: held.fiatMicros + topUp,
                sellFeeBps: held.sellFeeBps
            )
        } else {
            funded.append(CollectionFundingBalance(id: dollars, fiatMicros: topUp, sellFeeBps: 0))
        }
    }

    let heldDollars = balances.first { $0.id == dollars }?.fiatMicros ?? 0
    let legs = fundingLegs(amountMicros: amountMicros, balances: funded, paying: paying, dollars: dollars)
        .map { leg in
            guard leg.source == dollars else { return leg }
            let fromBalance = min(heldDollars, leg.soldMicros)
            return CollectionFundingPlan.Leg(
                source: leg.source,
                conversion: leg.conversion,
                soldMicros: leg.soldMicros,
                feeMicros: leg.feeMicros,
                deliveredMicros: leg.deliveredMicros,
                dollarsSplit: CollectionFundingPlan.DollarsSplit(
                    fromBalanceMicros: fromBalance,
                    fromTopUpMicros: leg.soldMicros - fromBalance
                )
            )
        }

    return CollectionFundingPlan(
        amountMicros: amountMicros,
        payingCurrency: paying,
        shortfallMicros: shortfall,
        topUpMicros: topUp,
        legs: legs
    )
}

// MARK: - Legs -

/// The legs that cover `amountMicros` from `balances`, in funding order, without Dollars splits.
private func fundingLegs(
    amountMicros: Int64,
    balances: [CollectionFundingBalance],
    paying: String,
    dollars: String
) -> [CollectionFundingPlan.Leg] {
    var order: [CollectionFundingBalance] = []
    if let payingBalance = balances.first(where: { $0.id == paying }) {
        order.append(payingBalance)
    }
    if paying != dollars, let dollarsBalance = balances.first(where: { $0.id == dollars }) {
        order.append(dollarsBalance)
    }
    order += balances
        .filter { $0.id != paying && $0.id != dollars }
        .sorted { ($0.fiatMicros, $0.id) < ($1.fiatMicros, $1.id) }

    var legs: [CollectionFundingPlan.Leg] = []
    var remaining = amountMicros
    for balance in order {
        guard remaining > 0 else { break }
        let held = balance.fiatMicros
        guard held > 0 else { continue }

        if balance.id == paying {
            let used = min(held, remaining)
            legs.append(CollectionFundingPlan.Leg(
                source: balance.id,
                conversion: false,
                soldMicros: used,
                feeMicros: 0,
                deliveredMicros: used,
                dollarsSplit: nil
            ))
            remaining -= used
            continue
        }

        let bps = sellFeeBps(balance, dollars: dollars)
        let drainFee = sellFeeMicros(held, bps: bps)
        let sold: Int64
        let fee: Int64
        // The drain test comes first: at a half-micro fee tie, grossing up what is still needed
        // lands a micro under the balance and would strand that micro.
        if held - drainFee <= remaining {
            sold = held
            fee = drainFee
        } else {
            sold = min(grossedUpMicros(remaining, bps: bps), held)
            fee = sellFeeMicros(sold, bps: bps)
        }
        legs.append(CollectionFundingPlan.Leg(
            source: balance.id,
            conversion: true,
            soldMicros: sold,
            feeMicros: fee,
            deliveredMicros: sold - fee,
            dollarsSplit: nil
        ))
        remaining -= sold - fee
    }
    return legs
}

// MARK: - Fee Math -

private let basisPointsPerWhole: Int64 = 10_000

/// The sell fee in basis points a source pays, clamped to 0...10⁴; Dollars always sell at none.
private func sellFeeBps(_ balance: CollectionFundingBalance, dollars: String) -> Int64 {
    guard balance.id != dollars else { return 0 }
    return min(max(balance.sellFeeBps, 0), basisPointsPerWhole)
}

/// What `balance` can put toward the payment: the full balance for the paying currency and
/// Dollars, `b − fee(b)` for any other.
///
/// Computed as `b − fee(b)` rather than `round(b × (1 − bps/10⁴))`, which differs by a micro when
/// the fee is a half-micro tie.
private func spendableMicros(_ balance: CollectionFundingBalance, paying: String, dollars: String) -> Int64 {
    guard balance.id != paying else { return balance.fiatMicros }
    let bps = sellFeeBps(balance, dollars: dollars)
    return balance.fiatMicros - sellFeeMicros(balance.fiatMicros, bps: bps)
}

/// `round(micros × bps / 10⁴)`, half-up.
private func sellFeeMicros(_ micros: Int64, bps: Int64) -> Int64 {
    fundingHalfUp(micros, times: bps, over: basisPointsPerWhole)
}

/// `round(micros / (1 − bps/10⁴))`, half-up: the amount to sell so that `micros` is left after the
/// fee. A 100% fee can't be grossed up, so it returns `micros` unchanged.
private func grossedUpMicros(_ micros: Int64, bps: Int64) -> Int64 {
    guard bps < basisPointsPerWhole else { return micros }
    return fundingHalfUp(micros, times: basisPointsPerWhole, over: basisPointsPerWhole - bps)
}

/// `round(value × multiplier / divisor)`, half-up, for a non-negative `value` and a `multiplier`
/// and positive `divisor` of at most 10⁴.
///
/// Splits `value` by `divisor` first so the product never overflows on a large balance.
func fundingHalfUp(_ value: Int64, times multiplier: Int64, over divisor: Int64) -> Int64 {
    let (quotient, remainder) = value.quotientAndRemainder(dividingBy: divisor)
    let (tailQuotient, tailRemainder) = (remainder * multiplier).quotientAndRemainder(dividingBy: divisor)
    return quotient * multiplier + tailQuotient + (2 * tailRemainder >= divisor ? 1 : 0)
}

/// The micros in one minor unit of a currency with `minorDigits` fraction digits: 10,000 for
/// two-digit currencies.
func microsPerMinorUnit(minorDigits: Int) -> Int64 {
    var unit: Int64 = 1
    for _ in 0..<max(0, 6 - minorDigits) {
        unit *= 10
    }
    return unit
}

/// Whether `micros` is worth less than half a minor unit, so it displays as zero when rounded
/// half-up: under 5,000 micros in a two-digit currency. Exactly half a unit displays as one and
/// is not dust.
func isDust(_ micros: Int64, minorUnitMicros: Int64) -> Bool {
    2 * micros < minorUnitMicros
}

/// `micros` rounded up to a whole number of minor units, still in micros.
func ceilMicros(_ micros: Int64, toMinorDigits minorDigits: Int) -> Int64 {
    let unit = microsPerMinorUnit(minorDigits: minorDigits)
    return (micros + unit - 1) / unit * unit
}
