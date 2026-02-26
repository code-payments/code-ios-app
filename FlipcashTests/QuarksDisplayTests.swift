//
//  QuarksDisplayTests.swift
//  FlipcashTests
//
//  Created by Claude on 2026-02-26.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Quarks Display Threshold")
struct QuarksDisplayTests {

    // MARK: - hasDisplayableValue

    @Test("USD exactly one cent is displayable")
    func hasDisplayableValue_USD_exactlyOneCent() {
        let quarks = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == true)
    }

    @Test("USD less than one cent is not displayable")
    func hasDisplayableValue_USD_lessThanOneCent() {
        let quarks = Quarks(quarks: 9_999 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == false)
    }

    @Test("USD one dollar is displayable")
    func hasDisplayableValue_USD_oneDollar() {
        let quarks = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == true)
    }

    @Test("USD single quark is not displayable")
    func hasDisplayableValue_USD_singleQuark() {
        let quarks = Quarks(quarks: 1 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == false)
    }

    @Test("JPY exactly one yen is displayable")
    func hasDisplayableValue_JPY_exactlyOneYen() {
        let quarks = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .jpy, decimals: 6)
        #expect(quarks.hasDisplayableValue == true)
    }

    @Test("JPY less than one yen is not displayable")
    func hasDisplayableValue_JPY_lessThanOneYen() {
        let quarks = Quarks(quarks: 999_999 as UInt64, currencyCode: .jpy, decimals: 6)
        #expect(quarks.hasDisplayableValue == false)
    }

    @Test("EUR less than one cent is not displayable")
    func hasDisplayableValue_EUR_lessThanOneCent() {
        let quarks = Quarks(quarks: 5_000 as UInt64, currencyCode: .eur, decimals: 6)
        #expect(quarks.hasDisplayableValue == false)
    }

    @Test("GBP exactly one penny is displayable")
    func hasDisplayableValue_GBP_exactlyOnePenny() {
        let quarks = Quarks(quarks: 10_000 as UInt64, currencyCode: .gbp, decimals: 6)
        #expect(quarks.hasDisplayableValue == true)
    }

    @Test("Zero quarks is not displayable")
    func hasDisplayableValue_zero() {
        let quarks = Quarks(quarks: 0 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == false)
    }

    @Test("Large amount is displayable")
    func hasDisplayableValue_largeAmount() {
        let quarks = Quarks(quarks: 1_000_000_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.hasDisplayableValue == true)
    }

    // MARK: - isApproximatelyZero

    @Test("USD sub-cent is approximately zero")
    func isApproximatelyZero_USD_subCent() {
        let quarks = Quarks(quarks: 1 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.isApproximatelyZero == true)
    }

    @Test("USD exactly one cent is not approximately zero")
    func isApproximatelyZero_USD_exactlyOneCent() {
        let quarks = Quarks(quarks: 10_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.isApproximatelyZero == false)
    }

    @Test("Zero is not approximately zero")
    func isApproximatelyZero_zero() {
        let quarks = Quarks(quarks: 0 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(quarks.isApproximatelyZero == false)
    }

    @Test("JPY sub-yen is approximately zero")
    func isApproximatelyZero_JPY_subYen() {
        let quarks = Quarks(quarks: 999_999 as UInt64, currencyCode: .jpy, decimals: 6)
        #expect(quarks.isApproximatelyZero == true)
    }
}
