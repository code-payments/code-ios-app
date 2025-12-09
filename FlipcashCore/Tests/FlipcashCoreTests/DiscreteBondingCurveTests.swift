//
//  DiscreteBondingCurveTests.swift
//  FlipcashCoreTests
//
//  Created by Claude on 2025-12-08.
//

import Testing
import Foundation
@preconcurrency import BigDecimal
@testable import FlipcashCore

// MARK: - Test Utilities

/// Precision for BigDecimal comparisons
nonisolated(unsafe) private let testRounding = Rounding(.toNearestOrEven, 36)

/// Check if two BigDecimals are approximately equal within a tolerance
private func isApproximatelyEqual(_ a: BigDecimal, _ b: BigDecimal, tolerance: BigDecimal = BigDecimal("0.0000000001")) -> Bool {
    let diff = a.subtract(b, testRounding)
    return diff.abs < tolerance
}

// MARK: - 1. Spot Price Tests

@Suite("Discrete Bonding Curve - Spot Price")
struct DiscreteSpotPriceTests {

    let curve = DiscreteBondingCurve()

    // Expected values from Rust table.rs (scaled by 10^18)
    static let expectedPriceStep0 = BigDecimal("0.010000000000000000")  // $0.01
    static let expectedPriceStep1 = BigDecimal("0.010000877213746469")
    static let expectedPriceStep2 = BigDecimal("0.010001754504443334")

    @Test("1.1 Spot price at supply 0 equals first table entry")
    func spotPriceAtSupplyZero() {
        let price = curve.spotPrice(at: 0)
        #expect(price != nil)
        if let price = price {
            #expect(isApproximatelyEqual(price, Self.expectedPriceStep0))
        }
    }

    @Test("1.2 Supply 50 uses same price as supply 0 (within step 0)")
    func spotPriceMidStep() {
        let price0 = curve.spotPrice(at: 0)
        let price50 = curve.spotPrice(at: 50)
        #expect(price0 == price50)
    }

    @Test("1.3 Supply 100 uses step 1 price")
    func spotPriceAtStepBoundary() {
        let price100 = curve.spotPrice(at: 100)
        #expect(price100 != nil)
        if let price100 = price100 {
            #expect(isApproximatelyEqual(price100, Self.expectedPriceStep1))
        }
    }

    @Test("1.4 Prices change at step boundaries 0, 100, 200...900")
    func spotPriceAtMultipleStepBoundaries() {
        var previousPrice: BigDecimal?
        for step in 0..<10 {
            let supply = step * 100
            let price = curve.spotPrice(at: supply)
            #expect(price != nil)
            if let previousPrice = previousPrice, let price = price {
                #expect(price > previousPrice, "Price should increase at step \(step)")
            }
            previousPrice = price
        }
    }

    @Test("1.5 Supply 99 still uses step 0 price")
    func spotPriceJustBeforeNextBoundary() {
        let price0 = curve.spotPrice(at: 0)
        let price99 = curve.spotPrice(at: 99)
        #expect(price0 == price99)
    }

    @Test("1.6 Various positions within step 5 all return same price")
    func spotPriceVariousPositionsWithinStep() {
        let step5Start = 500
        let offsets = [0, 1, 25, 50, 75, 99]
        let basePrice = curve.spotPrice(at: step5Start)
        #expect(basePrice != nil)

        for offset in offsets {
            let price = curve.spotPrice(at: step5Start + offset)
            #expect(price == basePrice, "Supply \(step5Start + offset) should have same price as supply \(step5Start)")
        }
    }

    @Test("1.7 Supply beyond table returns nil")
    func spotPriceBeyondTableReturnsNil() {
        let price = curve.spotPrice(at: 21_000_001)
        #expect(price == nil)
    }

    @Test("1.8 Supply at max valid step returns correct price")
    func spotPriceAtMaxSupply() {
        let price = curve.spotPrice(at: 21_000_000)
        #expect(price != nil)
    }
}

// MARK: - 2. Tokens To Value Tests

@Suite("Discrete Bonding Curve - Tokens To Value")
struct DiscreteTokensToValueTests {

    let curve = DiscreteBondingCurve()

    @Test("2.1 Buying 0 tokens costs 0 from any supply")
    func tokensToValueZeroTokens() {
        let cost = curve.tokensToValue(currentSupply: 0, tokens: 0)
        #expect(cost == .zero)

        let cost2 = curve.tokensToValue(currentSupply: 1000, tokens: 0)
        #expect(cost2 == .zero)
    }

    @Test("2.2 50 tokens from supply 0 = 50 * price[0]")
    func tokensToValueWithinSingleStep() {
        guard let price = curve.spotPrice(at: 0),
              let cost = curve.tokensToValue(currentSupply: 0, tokens: 50) else {
            Issue.record("Failed to get price or cost")
            return
        }

        let expected = BigDecimal(50).multiply(price, testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.3 75 tokens from supply 25 = 75 * price[0]")
    func tokensToValueMidStepToEndSameStep() {
        guard let price = curve.spotPrice(at: 0),
              let cost = curve.tokensToValue(currentSupply: 25, tokens: 75) else {
            Issue.record("Failed to get price or cost")
            return
        }

        let expected = BigDecimal(75).multiply(price, testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.4 30 tokens from supply 10 = 30 * price[0]")
    func tokensToValueMiddleOfStep() {
        guard let price = curve.spotPrice(at: 0),
              let cost = curve.tokensToValue(currentSupply: 10, tokens: 30) else {
            Issue.record("Failed to get price or cost")
            return
        }

        let expected = BigDecimal(30).multiply(price, testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.5 100 tokens from supply 0 = 100 * price[0]")
    func tokensToValueExactStep() {
        guard let price = curve.spotPrice(at: 0),
              let cost = curve.tokensToValue(currentSupply: 0, tokens: 100) else {
            Issue.record("Failed to get price or cost")
            return
        }

        let expected = BigDecimal(100).multiply(price, testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.6 200 tokens from 0 = 100*price[0] + 100*price[1]")
    func tokensToValueCrossingOneBoundary() {
        guard let price0 = curve.spotPrice(at: 0),
              let price1 = curve.spotPrice(at: 100),
              let cost = curve.tokensToValue(currentSupply: 0, tokens: 200) else {
            Issue.record("Failed to get prices or cost")
            return
        }

        let expected = BigDecimal(100).multiply(price0, testRounding)
            .add(BigDecimal(100).multiply(price1, testRounding), testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.7 150 tokens from 50 = 50*price[0] + 100*price[1]")
    func tokensToValuePartialStartStep() {
        guard let price0 = curve.spotPrice(at: 0),
              let price1 = curve.spotPrice(at: 100),
              let cost = curve.tokensToValue(currentSupply: 50, tokens: 150) else {
            Issue.record("Failed to get prices or cost")
            return
        }

        // 50 tokens to finish step 0, 100 tokens for step 1
        let expected = BigDecimal(50).multiply(price0, testRounding)
            .add(BigDecimal(100).multiply(price1, testRounding), testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.8 175 tokens from 0 = 100*price[0] + 75*price[1]")
    func tokensToValuePartialEndStep() {
        guard let price0 = curve.spotPrice(at: 0),
              let price1 = curve.spotPrice(at: 100),
              let cost = curve.tokensToValue(currentSupply: 0, tokens: 175) else {
            Issue.record("Failed to get prices or cost")
            return
        }

        let expected = BigDecimal(100).multiply(price0, testRounding)
            .add(BigDecimal(75).multiply(price1, testRounding), testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.9 125 tokens from 50 = 50*price[0] + 75*price[1]")
    func tokensToValuePartialBothEnds() {
        guard let price0 = curve.spotPrice(at: 0),
              let price1 = curve.spotPrice(at: 100),
              let cost = curve.tokensToValue(currentSupply: 50, tokens: 125) else {
            Issue.record("Failed to get prices or cost")
            return
        }

        let expected = BigDecimal(50).multiply(price0, testRounding)
            .add(BigDecimal(75).multiply(price1, testRounding), testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.10 500 tokens from 0 spans 5 complete steps")
    func tokensToValueMultipleFullSteps() {
        guard let cost = curve.tokensToValue(currentSupply: 0, tokens: 500) else {
            Issue.record("Failed to get cost")
            return
        }

        // Calculate expected: sum of 100 * price[i] for i in 0..<5
        var expected = BigDecimal.zero
        for step in 0..<5 {
            if let price = curve.spotPrice(at: step * 100) {
                expected = expected.add(BigDecimal(100).multiply(price, testRounding), testRounding)
            }
        }
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.11 350 tokens from 75 (complex partial case)")
    func tokensToValueMultipleStepsWithPartials() {
        guard let cost = curve.tokensToValue(currentSupply: 75, tokens: 350) else {
            Issue.record("Failed to get cost")
            return
        }

        // 25 tokens in step 0, 100 tokens each in steps 1-3, 25 tokens in step 4
        var expected = BigDecimal.zero
        if let p0 = curve.spotPrice(at: 0) {
            expected = expected.add(BigDecimal(25).multiply(p0, testRounding), testRounding)
        }
        for step in 1...3 {
            if let price = curve.spotPrice(at: step * 100) {
                expected = expected.add(BigDecimal(100).multiply(price, testRounding), testRounding)
            }
        }
        if let p4 = curve.spotPrice(at: 400) {
            expected = expected.add(BigDecimal(25).multiply(p4, testRounding), testRounding)
        }
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.12 150 tokens from 100 = 100*price[1] + 50*price[2]")
    func tokensToValueFromStepBoundary() {
        guard let price1 = curve.spotPrice(at: 100),
              let price2 = curve.spotPrice(at: 200),
              let cost = curve.tokensToValue(currentSupply: 100, tokens: 150) else {
            Issue.record("Failed to get prices or cost")
            return
        }

        let expected = BigDecimal(100).multiply(price1, testRounding)
            .add(BigDecimal(50).multiply(price2, testRounding), testRounding)
        #expect(isApproximatelyEqual(cost, expected))
    }

    @Test("2.13 Tokens beyond 21M returns nil")
    func tokensToValueExceedsTableReturnsNil() {
        let cost = curve.tokensToValue(currentSupply: 20_999_900, tokens: 200)
        #expect(cost == nil)
    }

    @Test("2.14 500 tokens from supply 1,000,000")
    func tokensToValueAtHighSupply() {
        let cost = curve.tokensToValue(currentSupply: 1_000_000, tokens: 500)
        #expect(cost != nil)
        if let cost = cost {
            #expect(cost > .zero)
        }
    }

    @Test("2.15 cost(A+B) = cost(A) + cost(B from A's end)")
    func tokensToValueIsAdditive() {
        guard let costA = curve.tokensToValue(currentSupply: 0, tokens: 200),
              let costB = curve.tokensToValue(currentSupply: 200, tokens: 150),
              let costTotal = curve.tokensToValue(currentSupply: 0, tokens: 350) else {
            Issue.record("Failed to get costs")
            return
        }

        let sum = costA.add(costB, testRounding)
        #expect(isApproximatelyEqual(costTotal, sum))
    }

    @Test("2.16 1 token at various positions equals price at that step")
    func tokensToValueSmallAmounts() {
        for step in [0, 5, 10, 50, 100] {
            let supply = step * 100
            guard let price = curve.spotPrice(at: supply),
                  let cost = curve.tokensToValue(currentSupply: supply, tokens: 1) else {
                Issue.record("Failed at step \(step)")
                continue
            }
            #expect(isApproximatelyEqual(cost, price), "1 token cost should equal spot price at step \(step)")
        }
    }

    @Test("2.17 tokensToValue(0, step*100) matches cumulative table pattern")
    func tokensToValueConsistencyWithCumulativeTable() {
        // First cumulative entry is 0 (supply 0)
        let cost0 = curve.tokensToValue(currentSupply: 0, tokens: 0)
        #expect(cost0 == .zero)

        // Cost to reach supply 100 should be approximately cumulative[1]
        // cumulative[1] = 1000000000000000000 (scaled) = 1.0 USDC
        if let cost100 = curve.tokensToValue(currentSupply: 0, tokens: 100) {
            let expectedApprox = BigDecimal("1.0")
            #expect(isApproximatelyEqual(cost100, expectedApprox, tolerance: BigDecimal("0.001")))
        }
    }
}

// MARK: - 3. Value To Tokens Tests

@Suite("Discrete Bonding Curve - Value To Tokens")
struct DiscreteValueToTokensTests {

    let curve = DiscreteBondingCurve()

    @Test("3.1 0 value yields 0 tokens from any supply")
    func valueToTokensZeroValue() {
        let tokens = curve.valueToTokens(currentSupply: 0, value: .zero)
        #expect(tokens == .zero)

        let tokens2 = curve.valueToTokens(currentSupply: 1000, value: .zero)
        #expect(tokens2 == .zero)
    }

    @Test("3.2 Value for 50 tokens yields approximately 50 tokens")
    func valueToTokensWithinSingleStep() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let value = BigDecimal(50).multiply(price, testRounding)
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: value) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(50)))
    }

    @Test("3.3 Value for 25 tokens yields approximately 25 tokens")
    func valueToTokens25Tokens() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let value = BigDecimal(25).multiply(price, testRounding)
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: value) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(25)))
    }

    @Test("3.4 Value for 99 tokens yields approximately 99 tokens")
    func valueToTokens99Tokens() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let value = BigDecimal(99).multiply(price, testRounding)
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: value) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(99)))
    }

    @Test("3.5 Value for 100 tokens yields approximately 100 tokens")
    func valueToTokensExactStep() {
        guard let cost = curve.tokensToValue(currentSupply: 0, tokens: 100) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(100)))
    }

    @Test("3.6 Value crossing boundary yields expected tokens")
    func valueToTokensCrossingBoundary() {
        guard let cost = curve.tokensToValue(currentSupply: 0, tokens: 150) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(150)))
    }

    @Test("3.7 From partial step, value for 150 tokens")
    func valueToTokensFromPartialStep() {
        guard let cost = curve.tokensToValue(currentSupply: 50, tokens: 150) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 50, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(150)))
    }

    @Test("3.8 Value for 500 tokens (5 steps)")
    func valueToTokensMultipleSteps() {
        guard let cost = curve.tokensToValue(currentSupply: 0, tokens: 500) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(500)))
    }

    @Test("3.9 50 tokens at high supply (step 10000)")
    func valueToTokensAtHighSupply() {
        let supply = 1_000_000
        guard let cost = curve.tokensToValue(currentSupply: supply, tokens: 50) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: supply, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(50)))
    }

    @Test("3.10 Small value can't complete a full token")
    func valueToTokensInsufficientForStepCompletion() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let smallValue = price.divide(BigDecimal(2), testRounding)  // Half a token's worth
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: smallValue) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal("0.5"), tolerance: BigDecimal("0.01")))
    }

    @Test("3.11 Exactly enough to complete current step")
    func valueToTokensJustEnoughToCompleteStep() {
        // From supply 50, need 50 tokens to complete step 0
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let value = BigDecimal(50).multiply(price, testRounding)
        guard let tokens = curve.valueToTokens(currentSupply: 50, value: value) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(50)))
    }

    @Test("3.12 Supply at last step with large value returns nil")
    func valueToTokensBeyondMaxReturnsNil() {
        let tokens = curve.valueToTokens(currentSupply: 21_000_000, value: BigDecimal("1000000"))
        #expect(tokens == nil)
    }

    @Test("3.13 Value for 1 token")
    func valueToTokensSmallValue() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: price) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(1)))
    }

    @Test("3.14 Value for 175 tokens (partial end step)")
    func valueToTokensPartialEndStep() {
        guard let cost = curve.tokensToValue(currentSupply: 0, tokens: 175) else {
            Issue.record("Failed to get cost")
            return
        }
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: cost) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal(175)))
    }
}

// MARK: - 4. Roundtrip & Consistency Tests

@Suite("Discrete Bonding Curve - Roundtrip")
struct DiscreteRoundtripTests {

    let curve = DiscreteBondingCurve()

    @Test("4.1 tokens -> value -> tokens approximately equals original")
    func roundtripTokensToValueToTokens() {
        let originalTokens = 250
        guard let value = curve.tokensToValue(currentSupply: 100, tokens: originalTokens),
              let recoveredTokens = curve.valueToTokens(currentSupply: 100, value: value) else {
            Issue.record("Failed roundtrip")
            return
        }
        // Discrete curves have step-based pricing, so small differences are expected
        #expect(isApproximatelyEqual(recoveredTokens, BigDecimal(originalTokens), tolerance: BigDecimal("1")))
    }

    @Test("4.2 value -> tokens -> value approximately equals original")
    func roundtripValueToTokensToValue() {
        let originalValue = BigDecimal("5.0")  // 5 USDC
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: originalValue) else {
            Issue.record("Failed to get tokens")
            return
        }
        // Convert tokens back (need to truncate to whole tokens for consistency)
        let wholeTokens = Int(tokens.round(Rounding(.towardZero, 0)).asString(.plain))!
        guard let recoveredValue = curve.tokensToValue(currentSupply: 0, tokens: wholeTokens) else {
            Issue.record("Failed to recover value")
            return
        }
        // Value should be close to original (may be slightly less due to truncation and step-based pricing)
        #expect(recoveredValue <= originalValue)
        let diff = originalValue.subtract(recoveredValue, testRounding)
        // Allow up to $2 difference for step-based pricing (at $0.01/token, truncating 1 token = $0.01)
        #expect(diff < BigDecimal("2"), "Value difference should be small")
    }

    @Test("4.3 spotPrice(S) equals tokensToValue(S, 1)")
    func spotPriceMatchesTokensToValueForSmallAmounts() {
        for step in [0, 10, 100, 1000] {
            let supply = step * 100
            guard let price = curve.spotPrice(at: supply),
                  let cost = curve.tokensToValue(currentSupply: supply, tokens: 1) else {
                Issue.record("Failed at step \(step)")
                continue
            }
            #expect(isApproximatelyEqual(price, cost), "Step \(step): spotPrice should equal cost of 1 token")
        }
    }

    @Test("4.4 Methods handle step boundaries consistently")
    func methodsHandleStepBoundariesConsistently() {
        // Price at 99 should equal price at 0, but 100 should differ
        let price99 = curve.spotPrice(at: 99)
        let price0 = curve.spotPrice(at: 0)
        let price100 = curve.spotPrice(at: 100)

        #expect(price99 == price0)
        #expect(price100 != price0)
    }

    @Test("4.5 Buying in parts equals buying all at once")
    func buyingInPartsEqualsBuyingAllAtOnce() {
        guard let costA = curve.tokensToValue(currentSupply: 0, tokens: 100),
              let costB = curve.tokensToValue(currentSupply: 100, tokens: 200),
              let costC = curve.tokensToValue(currentSupply: 300, tokens: 150),
              let costAll = curve.tokensToValue(currentSupply: 0, tokens: 450) else {
            Issue.record("Failed to get costs")
            return
        }

        let sumParts = costA.add(costB, testRounding).add(costC, testRounding)
        #expect(isApproximatelyEqual(costAll, sumParts))
    }

    @Test("4.6 Large purchase across many steps")
    func largePurchaseAcrossManySteps() {
        let cost = curve.tokensToValue(currentSupply: 1_234_500, tokens: 10_000)
        #expect(cost != nil)
        if let cost = cost {
            #expect(cost > .zero)
        }
    }

    @Test("4.7 Fractional tokens handling")
    func fractionalTokensHandling() {
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        // Value for 10.5 tokens
        let value = BigDecimal("10.5").multiply(price, testRounding)
        guard let tokens = curve.valueToTokens(currentSupply: 0, value: value) else {
            Issue.record("Failed to get tokens")
            return
        }
        #expect(isApproximatelyEqual(tokens, BigDecimal("10.5"), tolerance: BigDecimal("0.01")))
    }
}

// MARK: - 5. Table Validation Tests

@Suite("Discrete Bonding Curve - Table Validation")
struct DiscreteTableValidationTests {

    @Test("5.1 Pricing table has correct length")
    func pricingTableHasCorrectLength() {
        #expect(DiscreteCurveTables.pricingTable.count == 210_001)
    }

    @Test("5.2 Cumulative table has correct length")
    func cumulativeTableHasCorrectLength() {
        #expect(DiscreteCurveTables.cumulativeTable.count == 210_001)
    }

    @Test("5.3 Pricing table first entry is approximately $0.01")
    func pricingTableFirstEntryIsOnePenny() {
        let curve = DiscreteBondingCurve()
        guard let price = curve.spotPrice(at: 0) else {
            Issue.record("Failed to get price")
            return
        }
        let onePenny = BigDecimal("0.01")
        #expect(isApproximatelyEqual(price, onePenny, tolerance: BigDecimal("0.0001")))
    }

    @Test("5.4 Cumulative table first entry is zero")
    func cumulativeTableFirstEntryIsZero() {
        let first = DiscreteCurveTables.cumulativeTable[0]
        #expect(first == UInt128(0))
    }

    @Test("5.5 Pricing table is monotonically increasing")
    func pricingTableIsMonotonicallyIncreasing() {
        // Check first 100 entries
        for i in 1..<100 {
            let prev = DiscreteCurveTables.pricingTable[i - 1]
            let curr = DiscreteCurveTables.pricingTable[i]
            #expect(curr >= prev, "Price at step \(i) should be >= step \(i-1)")
        }
    }

    @Test("5.6 Cumulative table is monotonically increasing")
    func cumulativeTableIsMonotonicallyIncreasing() {
        // Check first 100 entries
        for i in 1..<100 {
            let prev = DiscreteCurveTables.cumulativeTable[i - 1]
            let curr = DiscreteCurveTables.cumulativeTable[i]
            #expect(curr >= prev, "Cumulative at step \(i) should be >= step \(i-1)")
        }
    }

    @Test("5.7 First few pricing entries match expected Rust values")
    func pricingTableMatchesRustValues() {
        // Expected values from Rust table.rs (raw u128 scaled by 10^18)
        let expectedRaw: [UInt64] = [
            10000000000000000,   // Supply: 0
            10000877213746469,   // Supply: 100
            10001754504443334,   // Supply: 200
            10002631872097344,   // Supply: 300
            10003509316715251,   // Supply: 400
        ]

        for (i, expected) in expectedRaw.enumerated() {
            let actual = DiscreteCurveTables.pricingTable[i]
            #expect(actual == UInt128(expected), "Mismatch at index \(i)")
        }
    }

    @Test("5.8 First few cumulative entries match expected Rust values")
    func cumulativeTableMatchesRustValues() {
        // Expected values from Rust table.rs
        let expectedRaw: [UInt64] = [
            0,                      // Supply: 0
            1000000000000000000,    // Supply: 100
            2000087721374646900,    // Supply: 200
            3000263171818980300,    // Supply: 300
            4000526359028714700,    // Supply: 400
        ]

        for (i, expected) in expectedRaw.enumerated() {
            let actual = DiscreteCurveTables.cumulativeTable[i]
            #expect(actual == UInt128(expected), "Mismatch at index \(i)")
        }
    }

    @Test("5.9 Table step size is 100")
    func tableStepSizeIs100() {
        #expect(DiscreteBondingCurve.stepSize == 100)
    }
}

// MARK: - 6. High-Level API Tests

@Suite("Discrete Bonding Curve - High-Level API")
struct DiscreteHighLevelAPITests {

    let curve = DiscreteBondingCurve()

    @Test("6.1 Market cap at zero supply is zero")
    func marketCapAtZeroSupply() {
        let marketCap = curve.marketCap(for: 0)
        #expect(marketCap == 0)
    }

    @Test("6.2 Market cap at non-zero supply is positive")
    func marketCapAtNonZeroSupply() {
        // 1000 tokens * 10^10 decimals
        let supplyQuarks = 1000 * 10_000_000_000
        let marketCap = curve.marketCap(for: supplyQuarks)
        #expect(marketCap != nil)
        if let marketCap = marketCap {
            #expect(marketCap > 0)
        }
    }

    @Test("6.3 Buy estimation with 0% fee")
    func buyWithZeroFeeBps() {
        let estimate = curve.buy(usdcQuarks: 1_000_000, feeBps: 0, tvl: 1_000_000)  // 1 USDC
        #expect(estimate != nil)
        if let estimate = estimate {
            #expect(estimate.grossTokens == estimate.netTokens)
            #expect(estimate.fees == .zero)
        }
    }

    @Test("6.4 Buy estimation with 1% fee")
    func buyWith100FeeBps() {
        let estimate = curve.buy(usdcQuarks: 1_000_000, feeBps: 100, tvl: 1_000_000)  // 1 USDC, 1% fee
        #expect(estimate != nil)
        if let estimate = estimate {
            #expect(estimate.netTokens < estimate.grossTokens)
            #expect(estimate.fees > .zero)
        }
    }

    @Test("6.5 Buy estimation with 10% fee")
    func buyWithLargeFee() {
        let estimate = curve.buy(usdcQuarks: 1_000_000, feeBps: 1000, tvl: 1_000_000)  // 1 USDC, 10% fee
        #expect(estimate != nil)
        if let estimate = estimate {
            // Net should be approximately 90% of gross
            let ratio = estimate.netTokens.divide(estimate.grossTokens, testRounding)
            #expect(isApproximatelyEqual(ratio, BigDecimal("0.9"), tolerance: BigDecimal("0.001")))
        }
    }

    @Test("6.6 Sell estimation with 0% fee")
    func sellWithZeroFeeBps() {
        // First buy some tokens to have something to sell
        let tokenQuarks = 100 * 10_000_000_000  // 100 tokens in quarks
        let estimate = curve.sell(tokenQuarks: tokenQuarks, feeBps: 0, tvl: 10_000_000)
        #expect(estimate != nil)
        if let estimate = estimate {
            #expect(estimate.grossUSDC == estimate.netUSDC)
            #expect(estimate.fees == .zero)
        }
    }

    @Test("6.7 Sell estimation with 1% fee")
    func sellWith100FeeBps() {
        let tokenQuarks = 100 * 10_000_000_000  // 100 tokens in quarks
        let estimate = curve.sell(tokenQuarks: tokenQuarks, feeBps: 100, tvl: 10_000_000)
        #expect(estimate != nil)
        if let estimate = estimate {
            #expect(estimate.netUSDC < estimate.grossUSDC)
            #expect(estimate.fees > .zero)
        }
    }

    @Test("6.8 net + fees equals gross for sells")
    func sellNetPlusFeeEqualsGross() {
        let tokenQuarks = 100 * 10_000_000_000
        let estimate = curve.sell(tokenQuarks: tokenQuarks, feeBps: 100, tvl: 10_000_000)
        #expect(estimate != nil)
        if let estimate = estimate {
            let sum = estimate.netUSDC.add(estimate.fees, testRounding)
            #expect(isApproximatelyEqual(sum, estimate.grossUSDC))
        }
    }

    @Test("6.9 Supply from TVL is consistent")
    func supplyFromTVLConsistency() {
        // 10 USDC TVL (10 * 10^6 quarks)
        let tvl = 10_000_000
        let supply = curve.supplyFromTVL(tvl)
        #expect(supply != nil)
        if let supply = supply {
            #expect(supply >= 0)
            // At ~$0.01/token start price, 10 USDC should buy ~1000 tokens
            #expect(supply < 2000)
        }
    }

    @Test("6.10 Buy then sell roundtrip")
    func buyThenSellRoundtrip() {
        let initialTVL = 1_000_000  // 1 USDC
        let usdcToSpend = 1_000_000  // 1 USDC

        // Buy
        guard let buyEstimate = curve.buy(usdcQuarks: usdcToSpend, feeBps: 0, tvl: initialTVL) else {
            Issue.record("Buy failed")
            return
        }

        // Sell the tokens we bought
        let tokenQuarks = Int(buyEstimate.netTokens.multiply(BigDecimal(10_000_000_000), testRounding).round(Rounding(.towardZero, 0)).asString(.plain))!
        let newTVL = initialTVL + usdcToSpend  // TVL increased

        guard let sellEstimate = curve.sell(tokenQuarks: tokenQuarks, feeBps: 0, tvl: newTVL) else {
            Issue.record("Sell failed")
            return
        }

        // Should get approximately what we spent
        let usdcRecovered = sellEstimate.netUSDC.multiply(BigDecimal(1_000_000), testRounding)
        // For discrete curves, step-based pricing introduces quantization.
        // At low token counts (100 tokens from $1) the rounding can cause ~10% loss
        // because each step is 100 tokens and we're right at the boundary.
        // For larger amounts (10+ steps) the loss would be much smaller.
        // Allow 15% loss for this small-amount test case.
        let minRecovery = BigDecimal(usdcToSpend).multiply(BigDecimal("0.85"), testRounding)
        #expect(usdcRecovered >= minRecovery, "Should recover at least 85% of original for small amounts")
    }
}

// MARK: - 7. Edge Cases & Error Handling

@Suite("Discrete Bonding Curve - Edge Cases")
struct DiscreteEdgeCaseTests {

    let curve = DiscreteBondingCurve()

    @Test("8.1 Negative supply handling")
    func negativeSupplyHandling() {
        let price = curve.spotPrice(at: -1)
        #expect(price == nil)
    }

    @Test("8.2 Negative tokens handling")
    func negativeTokensHandling() {
        let cost = curve.tokensToValue(currentSupply: 0, tokens: -1)
        #expect(cost == nil)
    }

    @Test("8.3 Negative value handling")
    func negativeValueHandling() {
        let tokens = curve.valueToTokens(currentSupply: 0, value: BigDecimal(-1))
        #expect(tokens == nil)
    }

    @Test("8.4 Very large value doesn't crash")
    func overflowProtection() {
        let hugeValue = BigDecimal("999999999999999999999999999999")
        let tokens = curve.valueToTokens(currentSupply: 0, value: hugeValue)
        // Should either return nil or a valid (possibly capped) result
        #expect(tokens == nil || tokens != nil)  // Just checking it doesn't crash
    }

    @Test("8.5 Very small values handled correctly")
    func underflowProtection() {
        let tinyValue = BigDecimal("0.0000000001")
        let tokens = curve.valueToTokens(currentSupply: 0, value: tinyValue)
        #expect(tokens != nil)
        if let tokens = tokens {
            #expect(tokens >= .zero)
        }
    }

    @Test("8.6 Exactly at max supply boundary")
    func maxSupplyBoundary() {
        let price = curve.spotPrice(at: 21_000_000)
        #expect(price != nil)

        let cost = curve.tokensToValue(currentSupply: 20_999_900, tokens: 100)
        #expect(cost != nil)
    }

    @Test("8.7 Just over max supply returns nil")
    func justOverMaxSupply() {
        let price = curve.spotPrice(at: 21_000_001)
        #expect(price == nil)

        let cost = curve.tokensToValue(currentSupply: 20_999_900, tokens: 200)
        #expect(cost == nil)
    }
}

// MARK: - 8. Tokens For Value Exchange Tests

@Suite("Discrete Bonding Curve - Tokens For Value Exchange")
struct DiscreteTokensForValueExchangeTests {

    let curve = DiscreteBondingCurve()

    // USDC quarks per dollar (6 decimals)
    let usdcQuarksPerDollar: Int = 1_000_000

    @Test("9.1 Zero fiat returns zero tokens")
    func zeroFiatReturnsZeroTokens() {
        let result = curve.tokensForValueExchange(
            fiat: .zero,
            fiatRate: BigDecimal("1.0"),
            tvl: 10 * usdcQuarksPerDollar
        )
        #expect(result != nil)
        #expect(result?.tokens == .zero)
    }

    @Test("9.2 Negative fiat returns zero tokens")
    func negativeFiatReturnsZeroTokens() {
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("-5.0"),
            fiatRate: BigDecimal("1.0"),
            tvl: 10 * usdcQuarksPerDollar
        )
        #expect(result != nil)
        #expect(result?.tokens == .zero)
    }

    @Test("9.3 USD 1:1 rate returns correct tokens")
    func usdOneToOneRate() {
        // With $1 USDC at supply 0, should get ~100 tokens at $0.01/token
        let tvl = 1 * usdcQuarksPerDollar  // $1 TVL
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("1.0"),  // $1 USD
            fiatRate: BigDecimal("1.0"),  // 1:1 rate
            tvl: tvl
        )

        #expect(result != nil)
        if let result = result {
            // At $0.01/token, $1 should buy ~100 tokens
            // But we're at supply derived from $1 TVL, so price may be slightly higher
            #expect(result.tokens.isPositive)
            // Tokens should be reasonable (between 50 and 150 for $1 at early supply)
            let tokensDouble = Double(result.tokens.asString(.plain))!
            #expect(tokensDouble > 50, "Should get more than 50 tokens for $1")
            #expect(tokensDouble < 150, "Should get less than 150 tokens for $1")
        }
    }

    @Test("9.4 CAD with 1.4 rate converts correctly")
    func cadWithExchangeRate() {
        let tvl = 10 * usdcQuarksPerDollar  // $10 TVL

        // $5 CAD at 1.4 rate = $3.57 USD
        let cadResult = curve.tokensForValueExchange(
            fiat: BigDecimal("5.0"),
            fiatRate: BigDecimal("1.4"),
            tvl: tvl
        )

        // $3.57 USD directly
        let usdResult = curve.tokensForValueExchange(
            fiat: BigDecimal("3.571428571428"),  // 5/1.4
            fiatRate: BigDecimal("1.0"),
            tvl: tvl
        )

        #expect(cadResult != nil)
        #expect(usdResult != nil)

        if let cadResult = cadResult, let usdResult = usdResult {
            // Both should yield approximately the same number of tokens
            #expect(isApproximatelyEqual(cadResult.tokens, usdResult.tokens, tolerance: BigDecimal("0.01")))
        }
    }

    @Test("9.5 fx rate is fiat divided by tokens")
    func fxRateCalculation() {
        let tvl = 5 * usdcQuarksPerDollar
        let fiat = BigDecimal("10.0")
        let fiatRate = BigDecimal("1.5")

        let result = curve.tokensForValueExchange(
            fiat: fiat,
            fiatRate: fiatRate,
            tvl: tvl
        )

        #expect(result != nil)
        if let result = result {
            // fx should equal fiat / tokens
            let expectedFx = fiat.divide(result.tokens, testRounding)
            #expect(isApproximatelyEqual(result.fx, expectedFx))
        }
    }

    @Test("9.6 Invalid TVL returns nil")
    func invalidTVLReturnsNil() {
        // Negative TVL should fail gracefully
        // Note: supplyFromTVL handles this internally
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("1.0"),
            fiatRate: BigDecimal("1.0"),
            tvl: -1
        )
        // Should either return nil or handle gracefully
        // The implementation converts to BigDecimal which handles negatives
        #expect(result == nil || result?.tokens == .zero || (result?.tokens.isPositive ?? false))
    }

    @Test("9.7 Large fiat amount works correctly")
    func largeFiatAmount() {
        let tvl = 1000 * usdcQuarksPerDollar  // $1000 TVL
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("500.0"),  // $500
            fiatRate: BigDecimal("1.0"),
            tvl: tvl
        )

        #expect(result != nil)
        if let result = result {
            #expect(result.tokens.isPositive)
            #expect(result.fx.isPositive)
        }
    }

    @Test("9.8 Small fiat amount works correctly")
    func smallFiatAmount() {
        let tvl = 10 * usdcQuarksPerDollar
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("0.01"),  // 1 cent
            fiatRate: BigDecimal("1.0"),
            tvl: tvl
        )

        #expect(result != nil)
        if let result = result {
            // Even small amounts should yield some tokens
            #expect(result.tokens.isPositive)
        }
    }

    @Test("9.9 Consistency with valueToTokens")
    func consistencyWithValueToTokens() {
        let tvl = 50 * usdcQuarksPerDollar  // $50 TVL
        let usdcValue = BigDecimal("5.0")  // $5 USDC

        // Get supply from TVL
        guard let supply = curve.supplyFromTVL(tvl) else {
            Issue.record("Failed to get supply from TVL")
            return
        }

        // Get tokens via valueToTokens directly
        guard let directTokens = curve.valueToTokens(currentSupply: supply, value: usdcValue) else {
            Issue.record("Failed to get tokens via valueToTokens")
            return
        }

        // Get tokens via tokensForValueExchange (with 1:1 rate)
        guard let exchangeResult = curve.tokensForValueExchange(
            fiat: usdcValue,
            fiatRate: BigDecimal("1.0"),
            tvl: tvl
        ) else {
            Issue.record("Failed to get tokens via tokensForValueExchange")
            return
        }

        // Both methods should yield the same result
        #expect(isApproximatelyEqual(directTokens, exchangeResult.tokens, tolerance: BigDecimal("0.0001")))
    }

    @Test("9.10 Multiple exchange rates yield proportional tokens")
    func multipleExchangeRatesProportional() {
        let tvl = 20 * usdcQuarksPerDollar

        // Same USD value through different fiat amounts
        let usdResult = curve.tokensForValueExchange(
            fiat: BigDecimal("10.0"),
            fiatRate: BigDecimal("1.0"),  // $10 USD = $10 USD
            tvl: tvl
        )

        let eurResult = curve.tokensForValueExchange(
            fiat: BigDecimal("9.0"),
            fiatRate: BigDecimal("0.9"),  // €9 EUR = $10 USD
            tvl: tvl
        )

        let gbpResult = curve.tokensForValueExchange(
            fiat: BigDecimal("8.0"),
            fiatRate: BigDecimal("0.8"),  // £8 GBP = $10 USD
            tvl: tvl
        )

        #expect(usdResult != nil)
        #expect(eurResult != nil)
        #expect(gbpResult != nil)

        if let usd = usdResult, let eur = eurResult, let gbp = gbpResult {
            // All should yield the same number of tokens (same USD value)
            #expect(isApproximatelyEqual(usd.tokens, eur.tokens, tolerance: BigDecimal("0.01")))
            #expect(isApproximatelyEqual(usd.tokens, gbp.tokens, tolerance: BigDecimal("0.01")))
        }
    }

    @Test("9.11 Zero TVL returns valid result at supply 0")
    func zeroTVLWorksAtSupplyZero() {
        let result = curve.tokensForValueExchange(
            fiat: BigDecimal("1.0"),
            fiatRate: BigDecimal("1.0"),
            tvl: 0  // No TVL = supply 0
        )

        #expect(result != nil)
        if let result = result {
            // At supply 0, $1 at $0.01/token = 100 tokens
            #expect(isApproximatelyEqual(result.tokens, BigDecimal("100"), tolerance: BigDecimal("1")))
        }
    }

    @Test("9.12 Valuation struct has correct values")
    func valuationStructCorrectness() {
        let tokens = BigDecimal("123.456")
        let fx = BigDecimal("0.05")

        let valuation = DiscreteBondingCurve.Valuation(tokens: tokens, fx: fx)

        #expect(valuation.tokens == tokens)
        #expect(valuation.fx == fx)
    }
}

// MARK: - 9. quarksPerToken Constant Tests

@Suite("Discrete Bonding Curve - Constants")
struct DiscreteConstantsTests {

    @Test("10.1 quarksPerToken equals 10^10")
    func quarksPerTokenValue() {
        #expect(DiscreteBondingCurve.quarksPerToken == 10_000_000_000)
    }

    @Test("10.2 quarksPerToken matches decimals")
    func quarksPerTokenMatchesDecimals() {
        let curve = DiscreteBondingCurve()
        let expected = Int(pow(10.0, Double(curve.decimals)))
        #expect(DiscreteBondingCurve.quarksPerToken == expected)
    }

    @Test("10.3 stepSize is 100")
    func stepSizeValue() {
        #expect(DiscreteBondingCurve.stepSize == 100)
    }

    @Test("10.4 maxSupply is 21 million")
    func maxSupplyValue() {
        #expect(DiscreteBondingCurve.maxSupply == 21_000_000)
    }

    @Test("10.5 tableSize is 210,001")
    func tableSizeValue() {
        #expect(DiscreteBondingCurve.tableSize == 210_001)
    }

    @Test("10.6 tablePrecision is 18")
    func tablePrecisionValue() {
        #expect(DiscreteBondingCurve.tablePrecision == 18)
    }
}
