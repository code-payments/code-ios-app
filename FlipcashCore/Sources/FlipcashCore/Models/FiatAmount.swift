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

    /// Format for display, dropping the fraction when the amount is whole (`$11`,
    /// not `$11.00`) and keeping it when it isn't (`$2.50`). This is how amounts
    /// are shown in fixed-width controls, and the unabbreviated form the same
    /// controls hand to VoiceOver.
    ///
    /// Paired with Android's `Fiat.FormattingRule.Truncated`.
    public func formattedDroppingZeroFraction() -> String {
        formatted(minimumFractionDigits: value == value.rounded(to: 0) ? 0 : nil)
    }
}

// MARK: - Abbreviation -

extension FiatAmount {

    /// The scales an abbreviated figure steps through, ascending; the largest one
    /// the amount clears is the one it is printed in.
    private static let abbreviationScales: [(scale: Decimal, suffix: String)] = [
        (1_000, "K"),
        (1_000_000, "M"),
        (1_000_000_000, "B"),
        (1_000_000_000_000, "T"),
    ]

    /// The amount formatted to fit a fixed-width control, capped at `maxDigits`
    /// digits: anything under the first scale is formatted as usual, and larger
    /// amounts are scaled to K/M/B/T with only as many decimals as the cap leaves
    /// room for — trailing zeros dropped.
    ///
    /// The cap is what keeps a localized amount inside its button: a $20 tip stays
    /// `$20`, but the same tip in rupiah is 332,000, which shows as `332K` rather
    /// than overflowing. The scale is chosen from the value, not the currency, so a
    /// currency whose everyday amounts are large abbreviates on the same rule.
    ///
    /// Paired with Android's `Fiat.abbreviated(maxDigits:)` — the two produce the
    /// same string for the same amount. ``CompactCurrencyFormatStyle`` is the
    /// `FormatStyle` entry point onto this.
    public func formattedAbbreviated(maxDigits: Int = 3) -> String {
        guard value != 0 else { return formattedDroppingZeroFraction() }

        // Round to `maxDigits` significant digits before picking the scale, so a
        // value that carries into the next one (999,999 → 1M) is scaled by the one
        // it lands in rather than printed as "1,000K".
        let rounded = value.rounded(to: maxDigits - 1 - value.leadingExponent)

        guard let step = Self.abbreviationScales.last(where: { abs(rounded) >= $0.scale }) else {
            return formattedDroppingZeroFraction()
        }

        let scaled = rounded / step.scale
        let wholeDigits = scaled.leadingExponent + 1
        let fractionDigits = max(0, maxDigits - wholeDigits)

        return NumberFormatter.fiat(
            currency: currency,
            minimumFractionDigits: 0,
            maximumFractionDigits: fractionDigits,
            truncated: false,
            suffix: step.suffix,
        ).string(from: scaled as NSDecimalNumber)!
    }
}

private extension Decimal {
    /// The power of ten of the leading digit — `floor(log10(abs(self)))`. Zero has
    /// no leading digit and answers `0`.
    var leadingExponent: Int {
        var magnitude = abs(self)
        var exponent = 0
        while magnitude >= 10 {
            magnitude /= 10
            exponent += 1
        }
        while magnitude > 0, magnitude < 1 {
            magnitude *= 10
            exponent -= 1
        }
        return exponent
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
