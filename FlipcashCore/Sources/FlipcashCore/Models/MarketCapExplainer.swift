//
//  MarketCapExplainer.swift
//  FlipcashCore
//

import Foundation
// @preconcurrency: BigDecimal.Rounding not Sendable upstream.
@preconcurrency import BigDecimal

/// The numbers behind "How Market Cap Works": a continuous reserve axis along
/// the bonding curve with labeled ticks, the price and the holder's worth at any
/// point on it, the curve samples for the chart, and the ownership rows.
///
/// The slider axis is the reserve (dollars in the curve), `tokensToValue(0, S)`.
/// Supply at a stop comes from the curve's own inverse, never a closed form.
public struct MarketCapExplainer: Sendable {

    /// A position on the reserve axis.
    public struct Stop: Sendable, Equatable, Identifiable {
        /// Dollars in the curve at this supply.
        public let reserve: Foundation.Decimal
        /// Circulating supply in whole tokens at this reserve.
        public let supply: Foundation.Decimal
        /// Spot price per token at this supply, in USD.
        public let price: Foundation.Decimal
        /// Whether this is the currency's live position.
        public let isToday: Bool

        public var id: Foundation.Decimal { reserve }
    }

    /// A point on the curve, for the chart.
    public struct CurvePoint: Sendable, Equatable {
        public let supply: Double
        public let price: Double

        public init(supply: Double, price: Double) {
            self.supply = supply
            self.price = price
        }
    }

    /// The "Your Ownership" rows. Every holding-dependent value is nil without holdings.
    public struct Ownership: Sendable, Equatable {
        /// Whole tokens held.
        public let tokens: Foundation.Decimal?
        /// Today's spot price per token, in USD.
        public let price: Foundation.Decimal
        /// Held / circulating, as a fraction (0.01 = 1%).
        public let shareOfCirculating: Foundation.Decimal?
        /// Held / 21M max supply, as a fraction.
        public let shareOfMax: Foundation.Decimal?
    }

    /// The base reserve stops, in dollars.
    public static let fixedReserves: [Foundation.Decimal] = [5_000, 100_000, 1_000_000, 10_000_000]

    /// The chart reaches this many tokens past the selected supply.
    public static let chartLookahead: Int = 750_000

    /// Spacing of the chart's curve samples, in tokens.
    public static let sampleStride: Int = 25_000

    /// Lowest price the chart's y axis shows, in USD.
    public static let chartFloorPrice: Double = 0.01

    /// The labeled ticks sorted by reserve; exactly one has `isToday`.
    public let stops: [Stop]

    /// How close to Today's track position (as a fraction of the track) a drag
    /// reads as Today.
    public static let todayTrackTolerance: Double = 0.002

    /// The holder's balance in quarks, if known.
    public let heldQuarks: UInt64?

    private let curve: DiscreteBondingCurve

    /// Returns nil when the curve cannot price today's supply.
    public init?(todaySupplyQuarks: UInt64, heldQuarks: UInt64?, curve: DiscreteBondingCurve = DiscreteBondingCurve()) {
        self.curve = curve
        self.heldQuarks = heldQuarks

        let todaySupply = Foundation.Decimal(todaySupplyQuarks) / Foundation.Decimal(DiscreteBondingCurve.quarksPerToken)
        guard
            let todayReserve = curve.tokensToValue(currentSupply: BigDecimal.zero, tokens: BigDecimal(todaySupply.description))?.asDecimal(),
            let todayPrice = curve.spotPrice(at: Self.wholeTokens(todaySupply))?.asDecimal()
        else { return nil }

        var built = [Stop(reserve: todayReserve, supply: todaySupply, price: todayPrice, isToday: true)]
        let maxReserve = curve.tokensToValue(
            currentSupply: BigDecimal.zero,
            tokens: BigDecimal(DiscreteBondingCurve.maxSupply)
        )?.asDecimal() ?? todayReserve
        for reserve in Self.stopReserves(todayReserve: todayReserve, maxReserve: maxReserve)
        where (reserve - todayReserve).magnitude > todayReserve * Self.todayStopMergeFraction {
            guard let stop = Self.makeStop(curve: curve, reserve: reserve, isToday: false) else { continue }
            built.append(stop)
        }
        self.stops = built.sorted { $0.reserve < $1.reserve }
    }

    // MARK: - Stops

    /// A fixed stop this close to Today's reserve (as a fraction) is replaced by Today.
    private static let todayStopMergeFraction = Foundation.Decimal(string: "0.01")!

    /// The fixed reserves for a currency: the base stops, then ×10 stops while the
    /// largest is at most twice Today's reserve, never past the curve's own maximum.
    static func stopReserves(todayReserve: Foundation.Decimal, maxReserve: Foundation.Decimal) -> [Foundation.Decimal] {
        var reserves = fixedReserves
        while let largest = reserves.last, largest <= todayReserve * 2, largest * 10 <= maxReserve {
            reserves.append(largest * 10)
        }
        return reserves
    }

    public var todayStop: Stop { stops.first(where: \.isToday)! }

    public var todayIndex: Int { stops.firstIndex(where: \.isToday)! }

    /// Position on the track in 0...1, by log of the reserve.
    public func trackPosition(of stop: Stop) -> Double {
        guard let lo = stops.first, let hi = stops.last, lo.reserve < hi.reserve else { return 0 }
        let logLo = log(lo.reserve.doubleValue)
        let logHi = log(hi.reserve.doubleValue)
        return (log(stop.reserve.doubleValue) - logLo) / (logHi - logLo)
    }

    /// The reserve at the track's ends: min($5K, Today) and max($10M, Today).
    public var trackBounds: ClosedRange<Foundation.Decimal> {
        stops.first!.reserve...stops.last!.reserve
    }

    /// The point at a track position in 0...1, log-spaced by reserve. Near
    /// Today's own position it returns Today exactly.
    public func stop(atTrackPosition position: Double) -> Stop {
        let t = min(max(position, 0), 1)
        let today = todayStop
        if abs(t - trackPosition(of: today)) < Self.todayTrackTolerance { return today }
        if t == 0 { return stops.first! }
        if t == 1 { return stops.last! }
        let bounds = trackBounds
        let logLo = log(bounds.lowerBound.doubleValue)
        let logHi = log(bounds.upperBound.doubleValue)
        let reserve = Foundation.Decimal(exp(logLo + t * (logHi - logLo))).rounded(to: 2)
        return makeStop(reserve: reserve, isToday: false) ?? today
    }

    private func makeStop(reserve: Foundation.Decimal, isToday: Bool) -> Stop? {
        Self.makeStop(curve: curve, reserve: reserve, isToday: isToday)
    }

    private static func makeStop(curve: DiscreteBondingCurve, reserve: Foundation.Decimal, isToday: Bool) -> Stop? {
        let supply = curve.preciseSupplyFromValue(BigDecimal(reserve.description)).asDecimal()
        guard let price = curve.spotPrice(at: wholeTokens(supply))?.asDecimal() else { return nil }
        return Stop(reserve: reserve, supply: supply, price: price, isToday: isToday)
    }

    // MARK: - Valuation

    /// The held balance's fee-free sell value in USD if the supply were `stop.supply`.
    /// Nil when holdings are unknown or the curve can't value them.
    public func worth(at stop: Stop) -> Foundation.Decimal? {
        guard let heldQuarks else { return nil }
        let supplyQuarks = (stop.supply * Foundation.Decimal(DiscreteBondingCurve.quarksPerToken)).rounded(to: 0)
        return curve.sell(
            tokenQuarks: Int(heldQuarks),
            feeBps: 0,
            supplyQuarks: NSDecimalNumber(decimal: supplyQuarks).intValue
        )?.netUSDF.asDecimal()
    }

    // MARK: - Chart

    /// The chart's right edge, in whole tokens, for a selection.
    public func chartSupplyMax(for stop: Stop) -> Int {
        min(Self.wholeTokens(stop.supply) + Self.chartLookahead, DiscreteBondingCurve.maxSupply)
    }

    /// Fraction of the chart's width kept clear to the right of the selection,
    /// so its marker is never cut off at the edge.
    public static let chartEdgeMargin: Double = 0.04

    /// The chart's x domain for a selection: the curve's right edge, widened so
    /// the selected supply sits at least ``chartEdgeMargin`` inside it.
    public func chartXDomain(for stop: Stop) -> ClosedRange<Double> {
        let edge = Double(chartSupplyMax(for: stop))
        let supply = stop.supply.doubleValue
        return 0...max(edge, supply / (1 - Self.chartEdgeMargin))
    }

    /// Curve samples from zero to the chart's right edge, from the curve's spot price.
    public func curvePoints(for stop: Stop) -> [CurvePoint] {
        let xMax = chartSupplyMax(for: stop)
        var xs = Array(stride(from: 0, to: xMax, by: Self.sampleStride))
        xs.append(xMax)
        return xs.compactMap { x in
            guard let price = curve.spotPrice(at: x)?.asDecimal().doubleValue else { return nil }
            return CurvePoint(supply: Double(x), price: price)
        }
    }

    /// The chart's y range: `$0.01` to the price at the right edge.
    public func chartPriceRange(for stop: Stop) -> ClosedRange<Double> {
        let top = curve.spotPrice(at: chartSupplyMax(for: stop))?.asDecimal().doubleValue ?? Self.chartFloorPrice
        return Self.chartFloorPrice...max(top, Self.chartFloorPrice)
    }

    // MARK: - Ownership

    public var ownership: Ownership {
        let today = todayStop
        guard let heldQuarks else {
            return Ownership(tokens: nil, price: today.price, shareOfCirculating: nil, shareOfMax: nil)
        }
        let held = Foundation.Decimal(heldQuarks) / Foundation.Decimal(DiscreteBondingCurve.quarksPerToken)
        return Ownership(
            tokens: held,
            price: today.price,
            shareOfCirculating: today.supply > 0 ? held / today.supply : nil,
            shareOfMax: held / Foundation.Decimal(DiscreteBondingCurve.maxSupply)
        )
    }

    private static func wholeTokens(_ supply: Foundation.Decimal) -> Int {
        NSDecimalNumber(decimal: supply.roundedDown(to: 0)).intValue
    }
}
