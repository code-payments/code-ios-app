//
//  Regression_698f4fe72b4e3bf592c9d523.swift
//  Flipcash
//
//  Hang: DiscreteBondingCurve.sell() passed unclamped tokensToSell to
//        tokensToValue(), causing endSupply to exceed the lookup table
//        bounds when tokenQuarks > supplyQuarks. The resulting
//        out-of-bounds table access hung the main thread in
//        BigDecimal destruction.
//
//  Fix: Pass the clamped `effectiveSell` (not `tokensToSell`) to
//       tokensToValue() so endSupply never exceeds currentSupply.
//

import Foundation
import Testing
// @preconcurrency: BigDecimal.Rounding not Sendable upstream.
@preconcurrency import BigDecimal
@testable import FlipcashCore

@Suite("Regression: 698f4fe – sell() hangs when tokenQuarks exceed supplyQuarks")
struct Regression_698f4fe {

    let curve = DiscreteBondingCurve()
    let quarksPerToken = DiscreteBondingCurve.quarksPerToken

    @Test("sell() with tokenQuarks exceeding supplyQuarks does not hang")
    func sellOversellDoesNotHang() {
        // Supply: 100 tokens. Attempt to sell 200 tokens.
        // Before the fix, endSupply = 0 + 200 = 200 which could exceed the
        // table range when paired with certain supply values, causing a hang.
        let supplyQuarks = 100 * quarksPerToken
        let tokenQuarks  = 200 * quarksPerToken

        let result = curve.sell(
            tokenQuarks: tokenQuarks,
            feeBps: 0,
            supplyQuarks: supplyQuarks
        )

        #expect(result != nil)
        if let result {
            #expect(result.grossUSDF.isPositive)
        }
    }

    @Test("sell() with tokenQuarks exceeding max supply does not hang or crash")
    func sellBeyondMaxSupplyDoesNotHang() {
        // Supply: 1,000 tokens. Attempt to sell 22,000,000 tokens (beyond max supply).
        // Before the fix, tokensToValue(supplyAfter=0, tokens=22M) computed
        // endStep = 220,000 which exceeds the 210,001-entry table, causing an
        // out-of-bounds read and a hang in BigDecimal destruction.
        let supplyQuarks = 1_000 * quarksPerToken
        let tokenQuarks  = (DiscreteBondingCurve.maxSupply + 1_000_000) * quarksPerToken

        let result = curve.sell(
            tokenQuarks: tokenQuarks,
            feeBps: 0,
            supplyQuarks: supplyQuarks
        )

        #expect(result != nil)
        if let result {
            #expect(result.grossUSDF.isPositive)
        }
    }

    @Test("sell() clamped value matches full supply valuation")
    func sellClampedValueMatchesFullSupply() {
        // When selling more than the supply, the result should equal selling
        // exactly the current supply (since effectiveSell is clamped).
        let supplyQuarks = 500 * quarksPerToken
        let exactTokenQuarks = 500 * quarksPerToken
        let oversellTokenQuarks = 1_000 * quarksPerToken

        let exactResult = curve.sell(
            tokenQuarks: exactTokenQuarks,
            feeBps: 0,
            supplyQuarks: supplyQuarks
        )

        let oversellResult = curve.sell(
            tokenQuarks: oversellTokenQuarks,
            feeBps: 0,
            supplyQuarks: supplyQuarks
        )

        #expect(exactResult != nil)
        #expect(oversellResult != nil)

        if let exact = exactResult, let oversell = oversellResult {
            #expect(exact.grossUSDF == oversell.grossUSDF,
                   "Overselling should yield the same value as selling the full supply")
        }
    }
}
