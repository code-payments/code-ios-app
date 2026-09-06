//
//  DiscreteBondingCurve.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-12-08.
//

import Foundation
// @preconcurrency: BigDecimal.Rounding not Sendable upstream.
@preconcurrency import BigDecimal
import SharedCoreKit

/// A discrete step-based bonding curve implementation that uses pre-computed
/// lookup tables for deterministic pricing across all clients.
///
/// The curve divides the token supply into steps of 100 tokens each.
/// Within each step, the price is constant (taken from the pricing table).
/// This ensures exact consistency with the Solana program implementation.
///
/// The table-driven pricing math is computed by the shared Kotlin engine
/// (`:libs:currency-math:discrete-curve`, exported through `SharedCoreKit`'s
/// `SharedBondingCurve`) so both platforms agree exactly -- this type only
/// loads the resource tables and converts to/from `BigDecimal` at the boundary.
public struct DiscreteBondingCurve: Sendable {

    // MARK: - Constants

    /// Step size in tokens (100 tokens per step)
    public static let stepSize: Int = 100

    /// Number of decimal places for table values (18, matching Rust)
    public static let tablePrecision: Int = 18

    /// Token decimals (10 decimal places)
    public let decimals: Int = 10

    /// Maximum token supply
    public static let maxSupply: Int = 21_000_000

    /// Number of steps in the tables (210,001 entries: 0 to 21,000,000 in steps of 100)
    public static let tableSize: Int = 210_001

    /// Quarks per whole token (10^10 for 10 decimal places)
    public static let quarksPerToken: Int = 10_000_000_000

    /// Rounding context for BigDecimal operations
    public static let rounding = Rounding(.toNearestOrEven, 50)

    // MARK: - Init

    public init() {}

    // MARK: - Table Loading

    /// Loads the pricing/cumulative tables into the shared Kotlin engine, once per process.
    /// `SharedBondingCurve.initialize` itself no-ops on a second call, so re-triggering this
    /// from another `DiscreteBondingCurve` instance is harmless.
    private static let tablesLoaded: Void = {
        guard
            let pricingURL = Bundle.module.url(forResource: "discrete_pricing_table", withExtension: "bin"),
            let cumulativeURL = Bundle.module.url(forResource: "discrete_cumulative_table", withExtension: "bin"),
            let pricingData = try? Data(contentsOf: pricingURL),
            let cumulativeData = try? Data(contentsOf: cumulativeURL)
        else {
            fatalError("Missing discrete curve table resources")
        }
        SharedBondingCurve.initialize(pricingTableBytes: pricingData, cumulativeTableBytes: cumulativeData)
    }()

    // MARK: - Core Methods

    /// Returns the spot price at a given supply level.
    ///
    /// The price is constant within each step of 100 tokens.
    /// Supply 0-99 uses price[0], supply 100-199 uses price[1], etc.
    ///
    /// - Parameter supply: Current token supply (in whole tokens, not quarks)
    /// - Returns: Price per token in USDC, or nil if supply exceeds max
    public func spotPrice(at supply: Int) -> BigDecimal? {
        _ = Self.tablesLoaded
        guard let result = SharedBondingCurve.spotPriceAtSupply(supply: Int32(supply)) else {
            return nil
        }
        return BigDecimal(result)
    }

    /// Calculates the total cost to buy a number of tokens starting at a given supply.
    ///
    /// Convenience overload that delegates to the BigDecimal implementation.
    ///
    /// - Parameters:
    ///   - currentSupply: Current token supply (in whole tokens)
    ///   - tokens: Number of tokens to buy (in whole tokens)
    /// - Returns: Total cost in USDC, or nil if purchase would exceed max supply
    public func tokensToValue(currentSupply: Int, tokens: Int) -> BigDecimal? {
        tokensToValue(currentSupply: BigDecimal(currentSupply), tokens: BigDecimal(tokens))
    }

    /// Calculates the total cost to buy a number of tokens starting at a given supply.
    ///
    /// This handles partial steps at the start and end, and uses the cumulative
    /// table for efficient calculation of complete middle steps.
    ///
    /// - Parameters:
    ///   - currentSupply: Current token supply as BigDecimal (can have fractional tokens)
    ///   - tokens: Number of tokens to buy as BigDecimal (can have fractional tokens)
    /// - Returns: Total cost in USDC, or nil if purchase would exceed max supply
    public func tokensToValue(currentSupply: BigDecimal, tokens: BigDecimal) -> BigDecimal? {
        _ = Self.tablesLoaded
        guard let result = SharedBondingCurve.tokensToValue(
            currentSupply: currentSupply.asString(.plain),
            tokens: tokens.asString(.plain)
        ) else {
            return nil
        }
        return BigDecimal(result)
    }

    /// Calculates the number of tokens that can be purchased for a given value.
    ///
    /// This is the inverse of `tokensToValue`. It uses binary search on the
    /// cumulative table for efficient lookup.
    ///
    /// - Parameters:
    ///   - currentSupply: Current token supply (in whole tokens)
    ///   - value: Amount of USDC to spend
    /// - Returns: Number of tokens that can be purchased, or nil if at max supply
    public func valueToTokens(currentSupply: Int, value: BigDecimal) -> BigDecimal? {
        _ = Self.tablesLoaded
        guard let result = SharedBondingCurve.valueToTokens(
            currentSupply: Int32(currentSupply),
            value: value.asString(.plain)
        ) else {
            return nil
        }
        return BigDecimal(result)
    }

    /// Calculate precise supply from a given value with interpolation within steps.
    ///
    /// Unlike `supplyFromTVL` which returns step boundaries, this method
    /// interpolates within the step to give a more accurate supply value.
    ///
    /// - Parameter value: Total value in USDC (not quarks)
    /// - Returns: Supply as BigDecimal with fractional tokens
    private func preciseSupplyFromValue(_ value: BigDecimal) -> BigDecimal {
        _ = Self.tablesLoaded
        return BigDecimal(SharedBondingCurve.preciseSupplyFromValue(value: value.asString(.plain)))
    }

    /// Calculate supply from TVL using the cumulative table.
    ///
    /// Uses binary search on the cumulative table to find which step contains
    /// the given TVL. Returns the supply at the **start** of that step (the step
    /// boundary), not an interpolated value within the step.
    ///
    /// For example, if TVL corresponds to somewhere between step 5 and step 6,
    /// this returns `500` (step 5 boundary), not an interpolated value like `550`.
    /// This matches the Rust implementation's step-based lookup behavior.
    ///
    /// - Parameter tvlQuarks: Total value locked in USDC quarks (6 decimals)
    /// - Returns: Current supply in whole tokens at the step boundary
    public func supplyFromTVL(_ tvlQuarks: Int) -> Int? {
        _ = Self.tablesLoaded
        return Int(SharedBondingCurve.supplyFromTVL(tvlQuarks: Int64(tvlQuarks)))
    }

    /// Low-level primitive backing the high-level `tokensForValueExchange(fiat:fiatRate:supplyQuarks:)`
    /// below -- mirrors Android's `BondingCurve.tokensForValueExchange(currentValue, value)`.
    ///
    /// - Parameters:
    ///   - currentValue: Current TVL in USDC
    ///   - value: USDC value to exchange out of the current TVL
    /// - Returns: The tokens removed and the effective fx rate, or nil if the exchange is invalid
    ///   (value <= 0, value > currentValue, or the resulting tokens are <= 0)
    func tokensForValueExchange(currentValue: BigDecimal, value: BigDecimal) -> (tokens: BigDecimal, fx: BigDecimal)? {
        _ = Self.tablesLoaded
        guard let result = SharedBondingCurve.tokensForValueExchange(
            currentValue: currentValue.asString(.plain),
            value: value.asString(.plain)
        ) else {
            return nil
        }
        return (BigDecimal(result.tokens), BigDecimal(result.fx))
    }
}

// MARK: - High-Level API

extension DiscreteBondingCurve {

    /// Estimation result for a buy operation
    public struct BuyEstimation: Sendable {
        public let grossTokens: BigDecimal
        public let netTokens: BigDecimal
        public let fees: BigDecimal
    }

    /// Estimation result for a sell operation
    public struct SellEstimation: Sendable {
        public let grossUSDF: BigDecimal
        public let netUSDF: BigDecimal
        public let fees: BigDecimal
    }

    /// Result of a token valuation calculation
    public struct Valuation: Sendable {
        public let tokens: BigDecimal
        public let fx: BigDecimal

        public init(tokens: BigDecimal, fx: BigDecimal) {
            self.tokens = tokens
            self.fx = fx
        }
    }

    /// Calculate market cap at a given supply
    ///
    /// - Parameter supplyQuarks: Current supply in quarks (10 decimals)
    /// - Returns: Market cap in USDC
    public func marketCap(for supplyQuarks: Int) -> Foundation.Decimal? {
        let supply = supplyQuarks / Self.quarksPerToken
        guard let price = spotPrice(at: supply) else { return nil }
        return BigDecimal(supply).multiply(price, Self.rounding).asDecimal()
    }

    /// Estimate a buy operation
    ///
    /// - Parameters:
    ///   - usdcQuarks: Amount of USDC to spend (in quarks, 6 decimals)
    ///   - feeBps: Fee in basis points (100 = 1%)
    ///   - supplyQuarks: Current token supply in quarks (10 decimals)
    /// - Returns: Buy estimation with gross tokens, net tokens, and fees
    public func buy(usdcQuarks: Int, feeBps: Int, supplyQuarks: Int) -> BuyEstimation? {
        // Convert USDC quarks to USDC units
        let usdcValue = BigDecimal(usdcQuarks).divide(BigDecimal(1_000_000), Self.rounding)

        // Convert supply quarks to whole tokens
        let currentSupply = supplyQuarks / Self.quarksPerToken

        // Calculate tokens bought
        guard let grossTokens = valueToTokens(currentSupply: currentSupply, value: usdcValue) else {
            return nil
        }

        // Apply fee
        let feeMultiplier = BigDecimal(feeBps).divide(BigDecimal(10_000), Self.rounding)
        let fees = grossTokens.multiply(feeMultiplier, Self.rounding)
        let netTokens = grossTokens.subtract(fees, Self.rounding)

        return BuyEstimation(grossTokens: grossTokens, netTokens: netTokens, fees: fees)
    }

    /// Estimate a sell operation
    ///
    /// - Parameters:
    ///   - tokenQuarks: Amount of tokens to sell (in quarks, 10 decimals)
    ///   - feeBps: Fee in basis points (100 = 1%)
    ///   - supplyQuarks: Current token supply in quarks (10 decimals)
    /// - Returns: Sell estimation with gross USDC, net USDC, and fees
    public func sell(tokenQuarks: Int, feeBps: Int, supplyQuarks: Int) -> SellEstimation? {
        // Convert token quarks to whole tokens
        let quarksPerToken = BigDecimal(Self.quarksPerToken)
        let tokensToSell = BigDecimal(tokenQuarks).divide(quarksPerToken, Self.rounding)

        // Convert supply quarks to whole tokens
        let currentSupply = BigDecimal(supplyQuarks).divide(quarksPerToken, Self.rounding)

        // If the balance exceeds the supply, assume the supply is the balance
        let effectiveSell = tokensToSell.clamped(to: .zero, and: currentSupply)
        let supplyAfter = currentSupply.subtract(effectiveSell, Self.rounding)

        // Calculate gross value using tokensToValue from supplyAfter
        guard let grossUSDF = tokensToValue(
            currentSupply: supplyAfter,
            tokens: effectiveSell
        ) else {
            return nil
        }

        // Apply fee
        let feeMultiplier = BigDecimal(feeBps).divide(BigDecimal(10_000), Self.rounding)
        let fees = grossUSDF.multiply(feeMultiplier, Self.rounding)
        let netUSDF = grossUSDF.subtract(fees, Self.rounding)

        return SellEstimation(grossUSDF: grossUSDF, netUSDF: netUSDF, fees: fees)
    }

    /// Calculate how many tokens can be obtained for a given fiat amount.
    ///
    /// - Parameters:
    ///   - fiat: Amount in local fiat currency (e.g., CAD)
    ///   - fiatRate: Exchange rate from fiat to USD (e.g., 1.4 for CAD/USD)
    ///   - supplyQuarks: Current token supply in quarks (10 decimals)
    /// - Returns: Valuation containing tokens received and effective exchange rate
    public func tokensForValueExchange(fiat: BigDecimal, fiatRate: BigDecimal, supplyQuarks: Int) -> Valuation? {
        guard fiat.isPositive else {
            return nil
        }

        // Convert fiat to USDC value (in USDC units, not quarks)
        let usdcValue = fiat.divide(fiatRate, Self.rounding)

        guard usdcValue.isPositive else {
            return nil
        }

        // Convert supply quarks to whole tokens using BigDecimal to preserve
        // fractional precision
        let quarksPerToken = BigDecimal(Self.quarksPerToken)
        let currentSupply = BigDecimal(supplyQuarks).divide(quarksPerToken, Self.rounding)

        // Calculate TVL from supply using BigDecimal overload (value of all tokens from 0 to currentSupply)
        guard let currentTVL = tokensToValue(currentSupply: BigDecimal.zero, tokens: currentSupply) else {
            return nil
        }

        // Cannot exchange more value than exists in TVL
        guard usdcValue <= currentTVL else {
            return nil
        }

        // Tokens = difference in supply between currentTVL and currentTVL - usdcValue
        guard let (tokens, _) = tokensForValueExchange(currentValue: currentTVL, value: usdcValue) else {
            return nil
        }

        // Calculate effective exchange rate: fiat per token
        let fx = fiat.divide(tokens, Self.rounding)

        return Valuation(tokens: tokens, fx: fx)
    }
}

// MARK: - BigDecimal Extensions

private extension BigDecimal {
    /// Clamps this value to the given range
    func clamped(to lower: BigDecimal, and upper: BigDecimal) -> BigDecimal {
        if self < lower {
            return lower
        } else if self > upper {
            return upper
        }
        return self
    }
}
