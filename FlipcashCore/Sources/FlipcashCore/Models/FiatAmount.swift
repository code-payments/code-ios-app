//
//  FiatAmount.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-20.
//

import Foundation

/// Fiat monetary value. Mirrors the proto `(currency, nativeAmount)` pair.
///
/// No decimals field — scaling is not a fiat concern.
public struct FiatAmount: Equatable, Hashable, Codable, Sendable {

    public let value: Decimal
    public let currency: CurrencyCode

    public init(value: Decimal, currency: CurrencyCode) {
        self.value = value
        self.currency = currency
    }

    public static func zero(in currency: CurrencyCode) -> FiatAmount {
        FiatAmount(value: 0, currency: currency)
    }

    /// Convenience for USD values.
    public static func usd(_ value: Decimal) -> FiatAmount {
        FiatAmount(value: value, currency: .usd)
    }

    public var doubleValue: Double { value.doubleValue }

    public var isPositive: Bool { value > 0 }
}

// MARK: - Arithmetic -

extension FiatAmount {
    public static func + (lhs: FiatAmount, rhs: FiatAmount) -> FiatAmount {
        precondition(lhs.currency == rhs.currency, "Cannot add FiatAmounts with different currencies")
        return FiatAmount(value: lhs.value + rhs.value, currency: lhs.currency)
    }

    public static func - (lhs: FiatAmount, rhs: FiatAmount) -> FiatAmount {
        precondition(lhs.currency == rhs.currency, "Cannot subtract FiatAmounts with different currencies")
        return FiatAmount(value: lhs.value - rhs.value, currency: lhs.currency)
    }

    public static func * (lhs: FiatAmount, rhs: Decimal) -> FiatAmount {
        FiatAmount(value: lhs.value * rhs, currency: lhs.currency)
    }
}

// MARK: - Comparable -

extension FiatAmount: Comparable {
    public static func < (lhs: FiatAmount, rhs: FiatAmount) -> Bool {
        precondition(lhs.currency == rhs.currency, "Cannot compare FiatAmounts with different currencies")
        return lhs.value < rhs.value
    }
}

// MARK: - Currency Conversion -

extension FiatAmount {
    /// Convert a USD value to another currency using a native-per-USD rate.
    /// Precondition: `self.currency == .usd`.
    public func converting(to rate: Rate) -> FiatAmount {
        precondition(currency == .usd, "converting(to:) assumes self is USD; use convertingToUSD(rate:) for the inverse")
        return FiatAmount(value: value * rate.fx, currency: rate.currency)
    }

    /// Convert a native-currency value to USD using a native-per-USD rate.
    /// Precondition: `self.currency == rate.currency`.
    public func convertingToUSD(rate: Rate) -> FiatAmount {
        precondition(currency == rate.currency, "rate.currency must match self.currency")
        return FiatAmount(value: value / rate.fx, currency: .usd)
    }

    /// This amount restated in `currency`, routed through USD the way the rate
    /// table is keyed, and rounded to the target's display precision. `nil` when
    /// either leg of the conversion has no rate.
    public func converted(to currency: CurrencyCode, rates: [CurrencyCode: Rate]) -> FiatAmount? {
        if self.currency == currency {
            return self
        }
        guard let ownRate = rates[self.currency] else { return nil }
        let usd = convertingToUSD(rate: ownRate)
        if currency == .usd {
            return usd.roundedToSmallestUnit()
        }
        guard let targetRate = rates[currency] else { return nil }
        return usd.converting(to: targetRate).roundedToSmallestUnit()
    }
}

// MARK: - Formatting -

extension FiatAmount {
    /// Format for display. `minimumFractionDigits` defaults to the currency's
    /// natural precision (2 for USD); pass `0` to strip trailing zeros on
    /// whole amounts (e.g. `"$10"` instead of `"$10.00"`).
    public func formatted(minimumFractionDigits: Int? = nil, suffix: String? = nil) -> String {
        NumberFormatter.fiat(
            currency: currency,
            minimumFractionDigits: minimumFractionDigits ?? currency.maximumFractionDigits,
            maximumFractionDigits: currency.maximumFractionDigits,
            truncated: false,
            suffix: suffix,
        ).string(from: value as NSDecimalNumber)!
    }
}

// MARK: - Abbreviation -

extension FiatAmount {

    /// The scales an abbreviated figure steps through, smallest first.
    private static let abbreviationSuffixes = ["K", "M", "B"]

    /// Format for a fixed-width slot where only three digits fit. Up to `$999`
    /// this is plain ``formatted(minimumFractionDigits:suffix:)``; past it the
    /// figure is scaled and suffixed — `$1.5K`, `$15K`, `$150K`, `$2.4M`, `$1B`.
    /// The scaled figure keeps a decimal only while it is a single digit, so the
    /// number never runs past three characters.
    ///
    /// The scale is chosen from the value, not the currency, so a currency whose
    /// natural amounts are large (¥, Rp) abbreviates on the same rule. Rounding
    /// is half-up like every other displayed figure, so `$10.5M` reads `$11M`.
    ///
    /// This is the one abbreviation rule; ``CompactCurrencyFormatStyle`` is the
    /// `FormatStyle` entry point onto it.
    public func formattedAbbreviated(minimumFractionDigits: Int? = nil) -> String {
        guard abs(value) >= 1000 else {
            return formatted(minimumFractionDigits: minimumFractionDigits)
        }

        var scaled = value / 1000
        var scale = 0
        while abs(scaled) >= 1000, scale < Self.abbreviationSuffixes.count - 1 {
            scaled /= 1000
            scale += 1
        }

        var fractionDigits = abs(scaled) < 10 ? 1 : 0
        var rounded = scaled.rounded(to: fractionDigits)
        // 999,999 scales to 999.999K, which rounds back into a fourth digit;
        // carry it up a scale ("$1M") rather than print "$1,000K". Values past
        // 999B have nowhere left to carry and stay in `B`.
        if abs(rounded) >= 1000, scale < Self.abbreviationSuffixes.count - 1 {
            scale += 1
            fractionDigits = 1
            rounded = (scaled / 1000).rounded(to: fractionDigits)
        }

        return NumberFormatter.fiat(
            currency: currency,
            minimumFractionDigits: 0,
            maximumFractionDigits: fractionDigits,
            truncated: false,
            suffix: Self.abbreviationSuffixes[scale],
        ).string(from: rounded as NSDecimalNumber)!
    }
}

// MARK: - Display Threshold -

extension FiatAmount {
    /// Whether this value would format as non-zero in `currency`.
    public var hasDisplayableValue: Bool {
        // Smallest fractional value the currency can render (e.g. USD → 0.01).
        let minimum = Decimal(sign: .plus, exponent: -currency.maximumFractionDigits, significand: 1)
        return value >= minimum
    }

    /// Non-zero but too small to display (would format as the currency's zero).
    public var isApproximatelyZero: Bool { value > 0 && !hasDisplayableValue }

    /// This value rounded to its currency's smallest displayable unit (e.g.
    /// $9.90099 → $9.90, $9.906 → $9.91) — the figure a user is shown, and so
    /// the figure any comparison against a displayed bound must use. Rounds
    /// half-up, matching `NumberFormatter.fiat`. Use
    /// ``flooredToSmallestUnit()`` instead for values that rounding up would
    /// break, such as a spend ceiling derived from a balance.
    public func roundedToSmallestUnit() -> FiatAmount {
        FiatAmount(
            value: value.rounded(to: currency.maximumFractionDigits),
            currency: currency
        )
    }

    /// This value truncated down to its currency's smallest displayable unit
    /// (e.g. $9.90099 → $9.90). For values whose defining invariant rounding up
    /// would break, such as a spend ceiling derived from a balance.
    public func flooredToSmallestUnit() -> FiatAmount {
        FiatAmount(
            value: value.roundedDown(to: currency.maximumFractionDigits),
            currency: currency
        )
    }
}

// MARK: - Description -

extension FiatAmount: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String      { formatted(suffix: nil) }
    public var debugDescription: String { description }
}
