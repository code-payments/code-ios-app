//
//  FiatAmount.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-20.
//

import Foundation

/// Fiat monetary value. Mirrors the proto `(currency, nativeAmount)` pair.
///
/// No decimals field — scaling is not a fiat concern. Callers that formerly
/// worked with `Quarks(.usd, decimals: 6)` now use `FiatAmount(currency: .usd)`.
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
}

// MARK: - Formatting -

extension FiatAmount {
    public func formatted(suffix: String? = nil) -> String {
        NumberFormatter.fiat(
            currency: currency,
            minimumFractionDigits: currency.maximumFractionDigits,
            maximumFractionDigits: currency.maximumFractionDigits,
            truncated: false,
            suffix: suffix,
        ).string(from: value as NSDecimalNumber)!
    }
}

// MARK: - Quarks Bridge -

extension FiatAmount {
    /// Render this fiat value as a `Quarks` at the currency's display precision.
    /// Negative values clamp to a zero `Quarks` to preserve the legacy
    /// `try?/?? zero` consumer pattern.
    public var asQuarks: Quarks {
        let decimals = currency.maximumFractionDigits
        return (try? Quarks(fiatDecimal: value, currencyCode: currency, decimals: decimals))
            ?? Quarks.zero(currencyCode: currency, decimals: decimals)
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
}

// MARK: - Description -

extension FiatAmount: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String      { formatted(suffix: nil) }
    public var debugDescription: String { description }
}
