//
//  Regression_698ef3b65e6cc4bb5554e13d.swift
//  Flipcash
//
//  Crash: UInt64.scaleUp arithmetic overflow when comparing Quarks
//         with different decimal precisions for high-rate currencies (CLP).
//
//  Fix: Quarks.< now compares via decimalValue (Decimal) instead of
//       aligning UInt64 quarks to a common precision via scaleUp.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Regression: 698ef3b – Quarks comparison overflow for high-rate currencies")
struct Regression_698ef3b {

    @Test("CLP quarks comparison across 6 and 10 decimal precisions does not overflow")
    func quarksComparison_CLP_doesNotOverflow() {
        // clpAt6:  475_000_000_000_000 / 10^6  = 475,000,000 CLP
        // clpAt10: 1_000_000_000_000_000_000 / 10^10 = 100,000,000 CLP
        let clpAt6  = Quarks(quarks: 475_000_000_000_000 as UInt64, currencyCode: .clp, decimals: 6)
        let clpAt10 = Quarks(quarks: 1_000_000_000_000_000_000 as UInt64, currencyCode: .clp, decimals: 10)

        // Must not crash, and 100M < 475M
        #expect(clpAt10 < clpAt6)
    }

    @Test("EnterAmountCalculator.maxEnterAmount with CLP does not overflow")
    func maxEnterAmount_CLP_doesNotOverflow() {
        let clpRate = Rate(fx: 950, currency: .clp)

        let underlying = Quarks(quarks: 500_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        let converted = Quarks(quarks: 475_000_000_000 as UInt64, currencyCode: .clp, decimals: 6)
        let balance = ExchangedFiat(
            underlying: underlying,
            converted: converted,
            rate: clpRate,
            mint: .usdf
        )

        let limit = Quarks(quarks: 950_000_000_000 as UInt64, currencyCode: .clp, decimals: 6)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .clp,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return limit },
            rateProvider: { _ in clpRate }
        )

        // Must not crash with arithmetic overflow
        let result = calculator.maxEnterAmount(maxBalance: balance)
        #expect(result == balance.converted)
    }

    @Test(
        "No currency overflows when comparing quarks across 6 and 10 decimal precisions",
        arguments: CurrencyCode.allCases
    )
    func quarksComparison_allCurrencies_noOverflow(currency: CurrencyCode) {
        let largeAt6  = Quarks(quarks: 1_000_000_000_000_000 as UInt64, currencyCode: currency, decimals: 6)
        let largeAt10 = Quarks(quarks: 1_000_000_000_000_000 as UInt64, currencyCode: currency, decimals: 10)

        // 10^15 / 10^6 = 10^9 vs 10^15 / 10^10 = 10^5
        #expect(largeAt10 < largeAt6)
    }
}
