//
//  DiscreteBondingCurve.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-12-08.
//

import Foundation
@preconcurrency import BigDecimal

/// A discrete step-based bonding curve implementation that uses pre-computed
/// lookup tables for deterministic pricing across all clients.
///
/// The curve divides the token supply into steps of 100 tokens each.
/// Within each step, the price is constant (taken from the pricing table).
/// This ensures exact consistency with the Solana program implementation.
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
    private static let rounding = Rounding(.toNearestOrEven, 36)

    // MARK: - Init

    public init() {}

    // MARK: - Core Methods

    /// Returns the spot price at a given supply level.
    ///
    /// The price is constant within each step of 100 tokens.
    /// Supply 0-99 uses price[0], supply 100-199 uses price[1], etc.
    ///
    /// - Parameter supply: Current token supply (in whole tokens, not quarks)
    /// - Returns: Price per token in USDC, or nil if supply exceeds max
    public func spotPrice(at supply: Int) -> BigDecimal? {
        guard supply >= 0, supply <= Self.maxSupply else { return nil }

        let stepIndex = supply / Self.stepSize
        guard stepIndex < DiscreteCurveTables.pricingTable.count else {
            return nil
        }

        return Self.fromScaledU128(DiscreteCurveTables.pricingTable[stepIndex])
    }

    /// Calculates the total cost to buy a number of tokens starting at a given supply.
    ///
    /// This handles partial steps at the start and end, and uses the cumulative
    /// table for efficient calculation of complete middle steps.
    ///
    /// - Parameters:
    ///   - currentSupply: Current token supply (in whole tokens)
    ///   - tokens: Number of tokens to buy (in whole tokens)
    /// - Returns: Total cost in USDC, or nil if purchase would exceed max supply
    public func tokensToValue(currentSupply: Int, tokens: Int) -> BigDecimal? {
        guard tokens >= 0, currentSupply >= 0 else { return nil }
        guard tokens > 0 else { return .zero }

        let endSupply = currentSupply + tokens
        let startStep = currentSupply / Self.stepSize
        let endStep = endSupply / Self.stepSize

        guard endStep < DiscreteCurveTables.pricingTable.count else {
            return nil
        }

        // Calculate partial tokens in start step (from currentSupply to next step boundary)
        let startStepBoundary = (startStep + 1) * Self.stepSize
        let tokensInStartStep: Int
        if startStepBoundary > endSupply {
            // All tokens are within the same step
            tokensInStartStep = tokens
        } else {
            tokensInStartStep = startStepBoundary - currentSupply
        }

        // Cost for partial start step
        let startPrice = Self.fromScaledU128(DiscreteCurveTables.pricingTable[startStep])
        let startCost = BigDecimal(tokensInStartStep).multiply(startPrice, Self.rounding)

        // If start and end are in the same step, we're done
        if startStep == endStep {
            return startCost
        }

        // Cost for complete steps between start_step+1 and end_step-1 (inclusive)
        // Use cumulative table: cumulative[end_step] - cumulative[start_step + 1]
        let cumulativeStart = Self.fromScaledU128(DiscreteCurveTables.cumulativeTable[startStep + 1])
        let cumulativeEnd = Self.fromScaledU128(DiscreteCurveTables.cumulativeTable[endStep])
        let middleCost = cumulativeEnd.subtract(cumulativeStart, Self.rounding)

        // Calculate partial tokens in end step (from end step boundary to end_supply)
        let endStepBoundary = endStep * Self.stepSize
        let tokensInEndStep = endSupply - endStepBoundary

        // Cost for partial end step
        let endPrice = Self.fromScaledU128(DiscreteCurveTables.pricingTable[endStep])
        let endCost = BigDecimal(tokensInEndStep).multiply(endPrice, Self.rounding)

        return startCost.add(middleCost, Self.rounding).add(endCost, Self.rounding)
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
        guard value.signum >= 0, currentSupply >= 0 else { return nil }
        guard value.isPositive else { return .zero }

        let startStep = currentSupply / Self.stepSize
        guard startStep < DiscreteCurveTables.pricingTable.count - 1 else {
            return nil
        }

        // Calculate cost to complete the current partial step
        let startStepBoundary = (startStep + 1) * Self.stepSize
        let tokensToCompleteStartStep = startStepBoundary - currentSupply
        let startPrice = Self.fromScaledU128(DiscreteCurveTables.pricingTable[startStep])
        let costToCompleteStartStep = BigDecimal(tokensToCompleteStartStep).multiply(startPrice, Self.rounding)

        // If we can't even complete the start step, just divide by price
        if value < costToCompleteStartStep {
            return value.divide(startPrice, Self.rounding)
        }

        // We can at least complete the start step
        let remainingAfterStart = value.subtract(costToCompleteStartStep, Self.rounding)

        // Calculate the cumulative value at start_step + 1 (where we'll be after completing start step)
        let baseCumulative = Self.fromScaledU128(DiscreteCurveTables.cumulativeTable[startStep + 1])

        // Target cumulative = base_cumulative + remaining_value
        let targetCumulative = baseCumulative.add(remainingAfterStart, Self.rounding)
        let targetCumulativeScaled = Self.toScaledU128(targetCumulative)

        // Binary search for the step where cumulative value exceeds or equals target
        var low = startStep + 1
        var high = DiscreteCurveTables.cumulativeTable.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            let midCumulative = DiscreteCurveTables.cumulativeTable[mid]

            if midCumulative <= targetCumulativeScaled {
                low = mid
            } else {
                high = mid - 1
            }
        }

        // low is now the last step where cumulative <= target
        let endStep = low

        guard endStep < DiscreteCurveTables.pricingTable.count else {
            return nil
        }

        // Calculate tokens from complete steps
        let endStepSupply = endStep * Self.stepSize
        let tokensFromCompleteSteps = endStepSupply - startStepBoundary

        // Calculate remaining value after complete steps
        let cumulativeAtEndStep = Self.fromScaledU128(DiscreteCurveTables.cumulativeTable[endStep])
        let valueUsedForCompleteSteps = cumulativeAtEndStep.subtract(baseCumulative, Self.rounding)
        let remainingValue = remainingAfterStart.subtract(valueUsedForCompleteSteps, Self.rounding)

        // Buy partial tokens in end step with remaining value
        let endPrice = Self.fromScaledU128(DiscreteCurveTables.pricingTable[endStep])
        let tokensInEndStep = remainingValue.divide(endPrice, Self.rounding)

        // Total tokens
        let total = BigDecimal(tokensToCompleteStartStep)
            .add(BigDecimal(tokensFromCompleteSteps), Self.rounding)
            .add(tokensInEndStep, Self.rounding)

        return total
    }

    // MARK: - Utility Methods

    /// Converts a scaled u128 value (18 decimals) to a BigDecimal
    private static func fromScaledU128(_ value: UInt128) -> BigDecimal {
        // Scale factor: 10^18
        let scaleFactor = BigDecimal("1000000000000000000")

        if value.high == 0 {
            // Simple case: fits in UInt64 - use String to avoid DPD encoding issue
            return BigDecimal(String(value.low)).divide(scaleFactor, rounding)
        }

        // value = high * 2^64 + low
        // Use string-based calculation for exactness
        // Note: BigDecimal(UInt64) interprets as DPD encoding, so use String instead
        let twoToThe64 = BigDecimal("18446744073709551616") // 2^64
        let highPart = BigDecimal(String(value.high)).multiply(twoToThe64, rounding)
        let combined = highPart.add(BigDecimal(String(value.low)), rounding)
        return combined.divide(scaleFactor, rounding)
    }

    /// Converts a BigDecimal to a scaled u128 value (18 decimals)
    private static func toScaledU128(_ value: BigDecimal) -> UInt128 {
        // Handle negative or zero values
        guard value.isPositive else {
            return UInt128(0)
        }

        let scaleFactor = BigDecimal.ten.pow(tablePrecision, rounding)
        let scaled = value.multiply(scaleFactor, rounding)

        // Get the integer part using truncation toward zero
        let floorRounding = Rounding(.towardZero, 0)
        let intPart = scaled.round(floorRounding)

        // Handle negative results from rounding
        guard intPart.isPositive || intPart.isZero else {
            return UInt128(0)
        }

        let str = intPart.asString(.plain)

        // Use the string-based UInt128 initializer which handles large numbers correctly
        if let result = UInt128(string: str) {
            return result
        }

        assertionFailure("Failed to parse UInt128 from string: \(str)")
        return UInt128(0)
    }
}

// MARK: - UInt128

/// A simple 128-bit unsigned integer for storing table values
public struct UInt128: Sendable, Equatable, Comparable {
    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// Initialize from a single UInt64 (fits in low bits)
    public init(_ value: UInt64) {
        self.high = 0
        self.low = value
    }

    /// Initialize from a decimal string representation
    /// Uses string-based arithmetic to avoid precision issues
    public init?(string: String) {
        // Remove any leading zeros
        var str = string
        while str.hasPrefix("0") && str.count > 1 {
            str.removeFirst()
        }

        // If it fits in UInt64, use that directly
        if let u64 = UInt64(str) {
            self.high = 0
            self.low = u64
            return
        }

        // For larger numbers, we need to divide by 2^64 using string arithmetic
        // 2^64 = 18446744073709551616
        let divisor = "18446744073709551616"

        // Perform long division
        var quotient = ""
        var remainder: UInt64 = 0

        for char in str {
            guard let digit = char.wholeNumberValue else {
                return nil
            }

            // remainder * 10 + digit
            let current = UInt64(remainder) * 10 + UInt64(digit)

            // This might overflow if remainder is large, so we need to handle it carefully
            // Actually, since we're processing digit by digit, the max intermediate value is
            // (2^64 - 1) * 10 + 9 which overflows UInt64
            // We need a different approach

            // Let's use a simpler approach: since we know the divisor is 2^64,
            // we can use the fact that the string represents a number = high * 2^64 + low
            // We can find the split point by checking string length

            break
        }

        // Alternative approach: find where to split the string
        // For numbers > 2^64, we can estimate the high part by taking leading digits
        // and computing low = original - high * 2^64

        // Actually, the cleanest approach is to use the decimal string directly
        // and compute high and low using repeated subtraction of 2^64

        // Since the string is guaranteed to be a positive integer, we can:
        // 1. Parse it as a very large number using an array of digits
        // 2. Divide by 2^64 to get high
        // 3. Take remainder for low

        // For simplicity, let's use a recursive subtraction approach
        var digits = str.compactMap { $0.wholeNumberValue }
        guard digits.count == str.count else { return nil }

        // Divide the digit array by 2^64
        let (highDigits, lowValue) = Self.divideByPow264(digits: digits)

        // Convert high digits back to UInt64
        var highValue: UInt64 = 0
        for digit in highDigits {
            highValue = highValue * 10 + UInt64(digit)
        }

        self.high = highValue
        self.low = lowValue
    }

    /// Divides a decimal number (represented as digits) by 2^64
    /// Returns (quotient digits, remainder as UInt64)
    private static func divideByPow264(digits: [Int]) -> ([Int], UInt64) {
        // 2^64 = 18446744073709551616
        let divisorDigits: [Int] = [1, 8, 4, 4, 6, 7, 4, 4, 0, 7, 3, 7, 0, 9, 5, 5, 1, 6, 1, 6]

        // If digits represent a number smaller than divisor, quotient is 0
        if digits.count < divisorDigits.count ||
           (digits.count == divisorDigits.count && compareDigits(digits, divisorDigits) < 0) {
            // Convert digits to UInt64
            var value: UInt64 = 0
            for d in digits {
                value = value * 10 + UInt64(d)
            }
            return ([], value)
        }

        // Perform long division
        var quotientDigits: [Int] = []
        var current: [Int] = []

        for digit in digits {
            current.append(digit)

            // Remove leading zeros from current
            while current.count > 1 && current.first == 0 {
                current.removeFirst()
            }

            // How many times does divisor fit in current?
            var count = 0
            while compareDigits(current, divisorDigits) >= 0 {
                current = subtractDigits(current, divisorDigits)
                count += 1
            }

            quotientDigits.append(count)
        }

        // Remove leading zeros from quotient
        while quotientDigits.count > 1 && quotientDigits.first == 0 {
            quotientDigits.removeFirst()
        }

        // Convert remainder (current) to UInt64
        var remainder: UInt64 = 0
        for d in current {
            remainder = remainder * 10 + UInt64(d)
        }

        return (quotientDigits, remainder)
    }

    /// Compare two digit arrays (returns -1, 0, or 1)
    private static func compareDigits(_ a: [Int], _ b: [Int]) -> Int {
        if a.count != b.count {
            return a.count < b.count ? -1 : 1
        }
        for (da, db) in zip(a, b) {
            if da != db {
                return da < db ? -1 : 1
            }
        }
        return 0
    }

    /// Subtract b from a (assumes a >= b)
    private static func subtractDigits(_ a: [Int], _ b: [Int]) -> [Int] {
        var result = a
        var borrow = 0

        // Pad b to match length of a
        let paddedB = Array(repeating: 0, count: a.count - b.count) + b

        for i in (0..<result.count).reversed() {
            var diff = result[i] - paddedB[i] - borrow
            if diff < 0 {
                diff += 10
                borrow = 1
            } else {
                borrow = 0
            }
            result[i] = diff
        }

        // Remove leading zeros
        while result.count > 1 && result.first == 0 {
            result.removeFirst()
        }

        return result
    }

    public static func < (lhs: UInt128, rhs: UInt128) -> Bool {
        if lhs.high != rhs.high {
            return lhs.high < rhs.high
        }
        return lhs.low < rhs.low
    }

    public static func <= (lhs: UInt128, rhs: UInt128) -> Bool {
        lhs < rhs || lhs == rhs
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
        public let grossUSDC: BigDecimal
        public let netUSDC: BigDecimal
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
    ///   - tvl: Current total value locked in quarks
    /// - Returns: Buy estimation with gross tokens, net tokens, and fees
    public func buy(usdcQuarks: Int, feeBps: Int, tvl: Int) -> BuyEstimation? {
        // Convert USDC quarks to USDC units
        let usdcValue = BigDecimal(usdcQuarks).divide(BigDecimal(1_000_000), Self.rounding)

        // Get current supply from TVL using cumulative table inverse lookup
        guard let currentSupply = supplyFromTVL(tvl) else { return nil }

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
    ///   - tvl: Current total value locked in quarks
    /// - Returns: Sell estimation with gross USDC, net USDC, and fees
    public func sell(tokenQuarks: Int, feeBps: Int, tvl: Int) -> SellEstimation? {
        // Convert token quarks to whole tokens
        let tokens = tokenQuarks / Self.quarksPerToken

        // Get current supply from TVL
        guard let currentSupply = supplyFromTVL(tvl) else { return nil }

        // New supply after selling
        let newSupply = currentSupply - tokens
        guard newSupply >= 0 else { return nil }

        // Value difference is the sell value
        guard let currentValue = tokensToValue(currentSupply: 0, tokens: currentSupply),
              let newValue = tokensToValue(currentSupply: 0, tokens: newSupply) else {
            return nil
        }

        let grossUSDC = currentValue.subtract(newValue, Self.rounding)

        // Apply fee
        let feeMultiplier = BigDecimal(feeBps).divide(BigDecimal(10_000), Self.rounding)
        let fees = grossUSDC.multiply(feeMultiplier, Self.rounding)
        let netUSDC = grossUSDC.subtract(fees, Self.rounding)

        return SellEstimation(grossUSDC: grossUSDC, netUSDC: netUSDC, fees: fees)
    }

    /// Calculate how many tokens can be obtained for a given fiat amount.
    ///
    /// Converts the fiat amount to USDC using the provided rate, then calculates
    /// how many tokens that USDC amount would purchase at the current TVL.
    ///
    /// - Parameters:
    ///   - fiat: Amount in local fiat currency (e.g., CAD)
    ///   - fiatRate: Exchange rate from fiat to USD (e.g., 1.4 for CAD/USD)
    ///   - tvl: Current total value locked in USDC quarks (6 decimals)
    /// - Returns: Valuation containing tokens received and effective exchange rate
    public func tokensForValueExchange(fiat: BigDecimal, fiatRate: BigDecimal, tvl: Int) -> Valuation? {
        guard fiat.isPositive else {
            return Valuation(tokens: .zero, fx: .zero)
        }

        // Convert fiat to USDC value
        let usdcValue = fiat.divide(fiatRate, Self.rounding)

        guard usdcValue.isPositive else {
            return Valuation(tokens: .zero, fx: .zero)
        }

        // Get current supply from TVL
        guard let currentSupply = supplyFromTVL(tvl) else {
            return nil
        }

        // Calculate tokens received for the USDC value
        guard let tokens = valueToTokens(currentSupply: currentSupply, value: usdcValue) else {
            return nil
        }

        guard tokens.isPositive else {
            return Valuation(tokens: .zero, fx: .zero)
        }

        // Calculate effective exchange rate: fiat per token
        let fx = fiat.divide(tokens, Self.rounding)

        return Valuation(tokens: tokens, fx: fx)
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
    /// - Returns: Current supply in whole tokens at the step boundary, or nil if invalid
    public func supplyFromTVL(_ tvlQuarks: Int) -> Int? {
        let tvl = BigDecimal(tvlQuarks).divide(BigDecimal(1_000_000), Self.rounding)
        let tvlScaled = Self.toScaledU128(tvl)

        // Binary search in cumulative table
        var low = 0
        var high = DiscreteCurveTables.cumulativeTable.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if DiscreteCurveTables.cumulativeTable[mid] <= tvlScaled {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low * Self.stepSize
    }
}

// MARK: - Lookup Tables

/// Pre-computed lookup tables for the discrete bonding curve.
///
/// Tables are loaded from binary resource files at runtime to avoid
/// Swift compiler memory issues with large array literals.
public enum DiscreteCurveTables {

    /// Spot price at each 100-token step (210,001 entries)
    /// Values are scaled by 10^18
    public static let pricingTable: [UInt128] = loadTable(named: "discrete_pricing_table")

    /// Cumulative cost from supply 0 to each step (210,001 entries)
    /// Values are scaled by 10^18
    public static let cumulativeTable: [UInt128] = loadTable(named: "discrete_cumulative_table")

    /// Load a lookup table from a binary resource file
    private static func loadTable(named name: String) -> [UInt128] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "bin") else {
            fatalError("Missing resource: \(name).bin")
        }

        guard let data = try? Data(contentsOf: url) else {
            fatalError("Failed to load resource: \(name).bin")
        }

        // Each entry is 16 bytes: low UInt64 (8 bytes) + high UInt64 (8 bytes)
        // Little-endian format
        let entrySize = 16
        let count = data.count / entrySize

        var result = [UInt128]()
        result.reserveCapacity(count)

        data.withUnsafeBytes { buffer in
            let ptr = buffer.bindMemory(to: UInt64.self)
            for i in 0..<count {
                let low = ptr[i * 2]
                let high = ptr[i * 2 + 1]
                result.append(UInt128(high: high, low: low))
            }
        }

        return result
    }
}
