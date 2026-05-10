//
//  ExchangedFiat.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-10.
//

import Foundation
import FlipcashAPI
import BigDecimal

/**
 * Represents a monetary value bridge between an on-chain token amount and its
 * localized fiat representation.
 *
 * Mirrors the server's `ExchangeData` proto: `(mint, quarks, nativeAmount,
 * currency, exchangeRate)`.
 *
 * - `onChainAmount` carries the mint-native integer that goes into the Solana
 *   SPL token transfer instruction and the `quarks` field of
 *   `Ocp_Transaction_V1_ExchangeData`.
 * - `nativeAmount` carries the user's fiat amount (e.g. CAD).
 * - `currencyRate.fx` is native-per-USD; combined with `nativeAmount` it yields
 *   the USD equivalent (see `usdfValue`).
 *
 * Example — sending $5 CAD worth of Jeffy at a 1.4 CAD/USD rate:
 *
 * ```
 * onChainAmount: Jeffy quarks being moved on-chain
 * nativeAmount:  5 CAD
 * currencyRate:  Rate(fx: 1.4, currency: .cad)
 * usdfValue:     ≈ $3.57 USD (computed: 5 / 1.4)
 * ```
 */
public struct ExchangedFiat: Equatable, Hashable, Codable, Sendable {

    /// The on-chain amount. Goes into `proto.quarks` and the SPL transfer.
    public let onChainAmount: TokenAmount

    /// The user's fiat amount in `currencyRate.currency`.
    public let nativeAmount: FiatAmount

    /// Currency FX rate: native-per-USD. Always. No per-token variant.
    public let currencyRate: Rate

    /// The mint of the on-chain token. Shorthand for `onChainAmount.mint`.
    public var mint: PublicKey { onChainAmount.mint }

    /// USD-denominated equivalent, derived from `nativeAmount` and `currencyRate`.
    public var usdfValue: FiatAmount {
        nativeAmount.convertingToUSD(rate: currencyRate)
    }

    // MARK: - Init -

    public init(
        onChainAmount: TokenAmount,
        nativeAmount: FiatAmount,
        currencyRate: Rate,
    ) {
        precondition(
            nativeAmount.currency == currencyRate.currency,
            "nativeAmount.currency must match currencyRate.currency",
        )
        self.onChainAmount = onChainAmount
        self.nativeAmount = nativeAmount
        self.currencyRate = currencyRate
    }

    /// Build from a user's native fiat amount for a USDF transfer.
    /// For bonded mints, use `compute(fromEntered:rate:mint:supplyQuarks:)`.
    public init(nativeAmount: FiatAmount, rate: Rate) {
        precondition(nativeAmount.currency == rate.currency)
        let usdfValue = nativeAmount.convertingToUSD(rate: rate)
        self.init(
            onChainAmount: TokenAmount(wholeTokens: usdfValue.value, mint: .usdf),
            nativeAmount: nativeAmount,
            currencyRate: rate,
        )
    }

    // MARK: - Factories -

    private static let bondingCurve = DiscreteBondingCurve()

    /// Build an `ExchangedFiat` from an on-chain amount. For bonded mints the
    /// USD-equivalent `nativeAmount` is resolved via the bonding curve using
    /// `supplyQuarks`; passing a nil/zero supply produces a safe zero.
    public static func compute(
        onChainAmount: TokenAmount,
        rate: Rate,
        supplyQuarks: UInt64?,
    ) -> ExchangedFiat {
        let mint = onChainAmount.mint

        if mint == .usdf {
            let usdfValue = FiatAmount.usd(onChainAmount.decimalValue)
            return ExchangedFiat(
                onChainAmount: onChainAmount,
                nativeAmount: usdfValue.converting(to: rate),
                currencyRate: rate,
            )
        }

        // Bonded: resolve USD equivalent via curve sell.
        guard let supplyQuarks, supplyQuarks > 0 else {
            return safeZero(mint: mint, rate: rate)
        }
        let quarksToSell = onChainAmount.quarks == 0 ? 1 : onChainAmount.quarks
        guard let valuation = bondingCurve.sell(
            tokenQuarks: Int(quarksToSell),
            feeBps: 0,
            supplyQuarks: Int(supplyQuarks),
        ) else {
            return safeZero(mint: mint, rate: rate)
        }

        let usdDecimal = onChainAmount.quarks == 0 ? .zero : valuation.netUSDF.asDecimal()
        let nativeAmount = FiatAmount.usd(usdDecimal).converting(to: rate)

        return ExchangedFiat(
            onChainAmount: onChainAmount,
            nativeAmount: nativeAmount,
            currencyRate: rate,
        )
    }

    /// Build an `ExchangedFiat` from a user-entered fiat amount.
    ///
    /// - Parameters:
    ///   - amount: User-entered fiat amount (in `rate.currency`).
    ///   - rate: Fiat FX rate for the selected currency.
    ///   - mint: Target token mint.
    ///   - supplyQuarks: Current token supply in quarks (10 decimals).
    ///   - balance: Optional USDF-equivalent balance cap. When provided the entered
    ///     amount is **silently capped** to this USD value. Use this for flows
    ///     (Buy/Sell) where FX rounding can cause the entered fiat to slightly
    ///     exceed the displayed balance. Do **not** pass a balance when the flow
    ///     should surface an insufficient-funds error instead of capping.
    ///   - tokenBalanceQuarks: Optional on-chain token balance cap (mint decimals).
    ///     Use this when the final token amount must never exceed the on-chain
    ///     balance (ex: sell flow where bonding-curve math can slightly overshoot).
    public static func compute(
        fromEntered amount: FiatAmount,
        rate: Rate,
        mint: PublicKey,
        supplyQuarks: UInt64,
        balance: FiatAmount? = nil,
        tokenBalanceQuarks: UInt64? = nil,
    ) -> ExchangedFiat? {
        guard amount.isPositive else { return nil }
        precondition(amount.currency == rate.currency)
        if let balance { precondition(balance.currency == .usd) }

        // Cap the entered amount to the USDF balance if provided.
        let usdRequested = amount.convertingToUSD(rate: rate)
        let cappedUSD: FiatAmount = {
            guard let balance else { return usdRequested }
            return usdRequested.value > balance.value ? balance : usdRequested
        }()

        // USDF-only path: onChain equals usdfValue (both at 6 decimals).
        if mint == .usdf {
            let onChain = TokenAmount(wholeTokens: cappedUSD.value, mint: .usdf)
            return ExchangedFiat(
                onChainAmount: onChain,
                nativeAmount: cappedUSD.converting(to: rate),
                currencyRate: rate,
            )
        }

        // Bonded: resolve token quarks via curve.
        let cappedNative = cappedUSD.converting(to: rate)
        guard let valuation = bondingCurve.tokensForValueExchange(
            fiat: BigDecimal(cappedNative.value),
            fiatRate: BigDecimal(rate.fx),
            supplyQuarks: Int(supplyQuarks),
        ) else { return nil }

        let tokenQuarks = valuation.tokens.asDecimal().scaleUpInt(mint.mintDecimals)

        // Cap to on-chain balance if provided (sell flow).
        if let tokenBalanceQuarks, tokenQuarks > tokenBalanceQuarks {
            return compute(
                onChainAmount: TokenAmount(quarks: tokenBalanceQuarks, mint: mint),
                rate: rate,
                supplyQuarks: supplyQuarks,
            )
        }

        // Round-trip through `compute(onChainAmount:)` so the fiat side matches
        // the server's intent validation (tokens → fiat via curve sell).
        return compute(
            onChainAmount: TokenAmount(quarks: tokenQuarks, mint: mint),
            rate: rate,
            supplyQuarks: supplyQuarks,
        )
    }

    private static func safeZero(mint: PublicKey, rate: Rate) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: .zero(mint: mint),
            nativeAmount: .zero(in: rate.currency),
            currencyRate: rate,
        )
    }

    // MARK: - Operations -

    /// Subtract another `ExchangedFiat` of the same mint and currency rate.
    /// Uses the direct `nativeAmount` delta — suitable when both sides are
    /// already exchanged (e.g. requested vs. balance) and re-running the
    /// bonding curve via `compute` would either drift on rounding or, if no
    /// supply is available, erase the delta into `safeZero`.
    public func subtracting(_ other: ExchangedFiat) -> ExchangedFiat {
        precondition(mint == other.mint, "Cannot subtract ExchangedFiats with different mints")
        precondition(currencyRate == other.currencyRate, "Cannot subtract ExchangedFiats with different currency rates")
        return ExchangedFiat(
            onChainAmount: onChainAmount - other.onChainAmount,
            nativeAmount: nativeAmount - other.nativeAmount,
            currencyRate: currencyRate,
        )
    }

    /// Add another `ExchangedFiat` of the same mint and currency rate.
    /// Symmetric to `subtracting(_:)` — uses direct `nativeAmount` addition to
    /// avoid re-running the bonding curve via `compute`.
    public func adding(_ other: ExchangedFiat) -> ExchangedFiat {
        precondition(mint == other.mint, "Cannot add ExchangedFiats with different mints")
        precondition(currencyRate == other.currencyRate, "Cannot add ExchangedFiats with different currency rates")
        return ExchangedFiat(
            onChainAmount: onChainAmount + other.onChainAmount,
            nativeAmount: nativeAmount + other.nativeAmount,
            currencyRate: currencyRate,
        )
    }

    /// Subtract an on-chain fee, scaling `nativeAmount` proportionally.
    /// For bonded mints this is a linear approximation of the bonding curve;
    /// at typical fee bps the deviation is below display rounding.
    public func subtractingFee(_ fee: TokenAmount) -> ExchangedFiat {
        let remaining = onChainAmount - fee
        let scale: Foundation.Decimal = onChainAmount.quarks > 0
            ? Foundation.Decimal(remaining.quarks) / Foundation.Decimal(onChainAmount.quarks)
            : 0
        return ExchangedFiat(
            onChainAmount: remaining,
            nativeAmount: nativeAmount * scale,
            currencyRate: currencyRate,
        )
    }

    /// Re-render this ExchangedFiat against a different currency rate.
    public func convert(to newRate: Rate) -> ExchangedFiat {
        ExchangedFiat(
            onChainAmount: onChainAmount,
            nativeAmount: usdfValue.converting(to: newRate),
            currencyRate: newRate,
        )
    }

    /// True if the `nativeAmount` would display as non-zero.
    public func hasDisplayableValue() -> Bool { nativeAmount.hasDisplayableValue }

    /// Non-zero but too small to display — use to decide whether to prefix with "~".
    public func isApproximatelyZero() -> Bool { nativeAmount.isApproximatelyZero }
}

// MARK: - Proto -

extension ExchangedFiat {
    /// Decode from proto exchange data. The proto carries the exchange rate
    /// directly, so no supply / curve is needed.
    public init(_ proto: Ocp_Transaction_V1_ExchangeData) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)
        self.init(
            onChainAmount: TokenAmount(quarks: proto.quarks, mint: mint),
            nativeAmount: FiatAmount(value: Decimal(proto.nativeAmount), currency: currency),
            currencyRate: Rate(fx: Decimal(proto.exchangeRate), currency: currency),
        )
    }

    /// Decode from `CryptoPaymentAmount`. This proto has no explicit exchange
    /// rate, so we synthesize one from `nativeAmount / onChainAmount.decimalValue`.
    /// For USDF mints that is the correct native-per-USD FX. For bonded mints
    /// it is a per-token rate; this matches the pre-existing behaviour and
    /// only the rate-display surface is affected.
    public init(_ proto: Flipcash_Common_V1_CryptoPaymentAmount) throws {
        let currency = try CurrencyCode(currencyCode: proto.currency)
        let mint     = try PublicKey(proto.mint.value)
        let onChain  = TokenAmount(quarks: proto.quarks, mint: mint)
        let native   = FiatAmount(value: Decimal(proto.nativeAmount), currency: currency)
        let fx: Foundation.Decimal = onChain.decimalValue > 0
            ? native.value / onChain.decimalValue
            : 1
        self.init(
            onChainAmount: onChain,
            nativeAmount: native,
            currencyRate: Rate(fx: fx, currency: currency),
        )
    }
}

// MARK: - Description -

extension ExchangedFiat {
    public var descriptionDictionary: [String: String] {
        [
            "usdf": usdfValue.formatted(suffix: nil),
            "onChainQuarks": "\(onChainAmount.quarks)",
            "mint": onChainAmount.mint.base58,
            "fx": currencyRate.fx.formatted(),
            "native": nativeAmount.formatted(suffix: nil),
            "currency": currencyRate.currency.rawValue.uppercased(),
        ]
    }
}

// MARK: - Collection -

extension Collection where Element == ExchangedFiat {
    /// Sum a collection of ExchangedFiats. Totals are summed in the provided
    /// display currency. `onChainAmount` is a USDF-minted placeholder since
    /// cross-mint totals have no meaningful single-mint representation.
    public func total(rate: Rate) -> ExchangedFiat {
        let nativeTotal = reduce(FiatAmount.zero(in: rate.currency)) { acc, ef in
            // Elements may have different currency rates; normalize by
            // converting each `usdfValue` through the provided rate.
            acc + ef.usdfValue.converting(to: rate)
        }
        let usdfTotal = nativeTotal.convertingToUSD(rate: rate)
        return ExchangedFiat(
            onChainAmount: TokenAmount(wholeTokens: usdfTotal.value, mint: .usdf),
            nativeAmount: nativeTotal,
            currencyRate: rate,
        )
    }
}
