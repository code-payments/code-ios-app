//
//  FiatTests.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import Testing
import FlipcashCore

@Suite("ExchangedFiat Tests")
struct ExchangedFiatTests {

    // USDC uses 6 decimals
    private static let usdcDecimals = 6

    @Test("Subtract fee from amount")
    func testSubtractingFeeFromAmount() throws {
        // subtracting(fee:) requires USD rate
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 5.00, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdc
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        let result = try exchangedFiat.subtracting(fee: fee)

        #expect(exchangedFiat.underlying.quarks == 5_000_000)
        #expect(fee.quarks == 500_000)
        #expect(result.underlying.quarks == 4_500_000)
    }

    @Test("Subtract fee too large")
    func testSubtractingFeeTooLarge() throws {
        // subtracting(fee:) requires USD rate
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 0.40, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdc
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        #expect(throws: ExchangedFiat.Error.feeLargerThanAmount) {
            try exchangedFiat.subtracting(fee: fee)
        }
    }

    @Test("Subtract fee equal to amount results in zero")
    func testSubtractingFeeEqualToAmount() throws {
        let exchangedFiat = try ExchangedFiat(
            converted: try Quarks(fiatDecimal: 0.50, currencyCode: .usd, decimals: Self.usdcDecimals),
            rate: .oneToOne,
            mint: .usdc
        )

        let fee = try Quarks(fiatDecimal: 0.5, currencyCode: .usd, decimals: Self.usdcDecimals)

        // When fee equals amount, result should be zero (not an error)
        let result = try exchangedFiat.subtracting(fee: fee)
        #expect(result.underlying.quarks == 0)
    }
}
