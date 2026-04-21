//
//  FiatAmountDisplayTests.swift
//  FlipcashTests
//
//  Created by Claude on 2026-02-26.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("FiatAmount Display Threshold")
struct FiatAmountDisplayTests {

    // MARK: - hasDisplayableValue

    @Test("USD exactly one cent is displayable")
    func hasDisplayableValue_USD_exactlyOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("USD less than one cent is not displayable")
    func hasDisplayableValue_USD_lessThanOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.009999")!, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("USD one dollar is displayable")
    func hasDisplayableValue_USD_oneDollar() {
        let amount = FiatAmount(value: 1, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("USD tiny sub-cent value is not displayable")
    func hasDisplayableValue_USD_subCent() {
        let amount = FiatAmount(value: Decimal(string: "0.000001")!, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("JPY exactly one yen is displayable")
    func hasDisplayableValue_JPY_exactlyOneYen() {
        let amount = FiatAmount(value: 1, currency: .jpy)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("JPY less than one yen is not displayable")
    func hasDisplayableValue_JPY_lessThanOneYen() {
        let amount = FiatAmount(value: Decimal(string: "0.999999")!, currency: .jpy)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("EUR less than one cent is not displayable")
    func hasDisplayableValue_EUR_lessThanOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.005")!, currency: .eur)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("GBP exactly one penny is displayable")
    func hasDisplayableValue_GBP_exactlyOnePenny() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .gbp)
        #expect(amount.hasDisplayableValue == true)
    }

    @Test("Zero is not displayable")
    func hasDisplayableValue_zero() {
        let amount = FiatAmount(value: 0, currency: .usd)
        #expect(amount.hasDisplayableValue == false)
    }

    @Test("Large amount is displayable")
    func hasDisplayableValue_largeAmount() {
        let amount = FiatAmount(value: 1_000_000, currency: .usd)
        #expect(amount.hasDisplayableValue == true)
    }

    // MARK: - isApproximatelyZero

    @Test("USD sub-cent is approximately zero")
    func isApproximatelyZero_USD_subCent() {
        let amount = FiatAmount(value: Decimal(string: "0.000001")!, currency: .usd)
        #expect(amount.isApproximatelyZero == true)
    }

    @Test("USD exactly one cent is not approximately zero")
    func isApproximatelyZero_USD_exactlyOneCent() {
        let amount = FiatAmount(value: Decimal(string: "0.01")!, currency: .usd)
        #expect(amount.isApproximatelyZero == false)
    }

    @Test("Zero is not approximately zero")
    func isApproximatelyZero_zero() {
        let amount = FiatAmount(value: 0, currency: .usd)
        #expect(amount.isApproximatelyZero == false)
    }

    @Test("JPY sub-yen is approximately zero")
    func isApproximatelyZero_JPY_subYen() {
        let amount = FiatAmount(value: Decimal(string: "0.999999")!, currency: .jpy)
        #expect(amount.isApproximatelyZero == true)
    }
}
