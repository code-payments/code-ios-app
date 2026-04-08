//
//  EnterAmountCalculatorTests.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-01-03.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite struct EnterAmountCalculatorTests {

    // MARK: - Test Helpers

    static func createExchangedFiat(
        underlyingQuarks: UInt64,
        convertedQuarks: UInt64,
        currency: CurrencyCode = .usd
    ) -> ExchangedFiat {
        let underlying = Quarks(quarks: underlyingQuarks, currencyCode: .usd, decimals: 6)
        let converted = Quarks(quarks: convertedQuarks, currencyCode: currency, decimals: 6)

        return ExchangedFiat(
            underlying: underlying,
            converted: converted,
            rate: Rate(fx: 1, currency: currency),
            mint: .usdf
        )
    }

    static func sendLimit(
        nextTransaction: UInt64,
        maxPerTransaction: UInt64,
        maxPerDay: UInt64,
        currency: CurrencyCode = .usd
    ) -> SendLimit {
        SendLimit(
            nextTransaction: Quarks(quarks: nextTransaction, currencyCode: currency, decimals: 6),
            maxPerTransaction: Quarks(quarks: maxPerTransaction, currencyCode: currency, decimals: 6),
            maxPerDay: Quarks(quarks: maxPerDay, currencyCode: currency, decimals: 6)
        )
    }

    // MARK: - Currency Tests

    @Test func currency_whenModeIsCurrency_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .cad)
    }

    @Test func currency_whenModeIsBuy_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .buy,
            entryCurrency: .eur,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .eur)
    }

    @Test func currency_whenModeIsSell_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .sell,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .cad)
    }

    @Test func currency_whenModeIsOnramp_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .onramp,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .usd)
    }

    @Test func currency_whenModeIsWithdraw_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .withdraw,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .cad)
    }

    @Test func currency_whenModeIsWalletDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .walletDeposit("Phantom"),
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .usd)
    }

    @Test func currency_whenModeIsPhantomDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .phantomDeposit,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.currency == .usd)
    }

    // MARK: - Max Transaction Amount Tests

    @Test func maxTransactionAmount_whenLimitIsNil_returnsNil() {
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.maxTransactionAmount == nil)
    }

    @Test func maxTransactionAmount_whenLimitExists_returnsLimit() {
        let sendLimit = Self.sendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit }
        )

        // Give mode: min(maxPerTransaction, nextTransaction) = $1.00
        #expect(calculator.maxTransactionAmount == sendLimit.maxPerTransaction)
    }

    // MARK: - Give Mode Limit Tests

    @Test("Give mode uses min(maxPerTransaction, nextTransaction) when daily partially used")
    func maxTransactionAmount_giveMode_partiallyUsedDaily_usesNextTransaction() {
        // $100 remaining, $250 per-tx cap, $1000 daily
        let sendLimit = Self.sendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in sendLimit }
        )

        // nextTransaction ($100) < maxPerTransaction ($250), so effective limit is $100
        #expect(calculator.maxTransactionAmount == sendLimit.nextTransaction)
    }

    @Test("Give mode on fresh day uses maxPerTransaction when nextTransaction equals it")
    func maxTransactionAmount_giveMode_freshDay_usesMaxPerTransaction() {
        // Fresh day: nextTransaction == maxPerTransaction ($250)
        let sendLimit = Self.sendLimit(nextTransaction: 250_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in sendLimit }
        )

        #expect(calculator.maxTransactionAmount == sendLimit.maxPerTransaction)
    }

    @Test("Give mode uses localized CAD limits without conversion")
    func maxTransactionAmount_giveMode_CAD_usesLocalizedLimitDirectly() {
        // Server already sends CAD-localized limits: $250 CAD per-tx cap.
        let sendLimit = Self.sendLimit(
            nextTransaction: 250_000_000,
            maxPerTransaction: 250_000_000,
            maxPerDay: 1_385_574_951,
            currency: .cad
        )

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .cad,
            sendLimitProvider: { _ in sendLimit }
        )

        // Must equal the server-provided CAD value, not double-converted via fx.
        #expect(calculator.maxTransactionAmount == sendLimit.maxPerTransaction)
        #expect(calculator.maxTransactionAmount?.currencyCode == .cad)
    }

    // MARK: - Buy-Style Mode Limit Tests

    static let buyStyleModes: [EnterAmountView.Mode] = [
        .buy,
        .phantomDeposit,
        .walletDeposit("Phantom"),
        .onramp,
    ]

    @Test("Buy-style modes use maxPerDay as per-transaction limit", arguments: buyStyleModes)
    func maxTransactionAmount_buyStyleModes_usesMaxPerDay(mode: EnterAmountView.Mode) {
        let sendLimit = Self.sendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: mode,
            entryCurrency: .usd,
            sendLimitProvider: { _ in sendLimit }
        )

        #expect(calculator.maxTransactionAmount == sendLimit.maxPerDay)
    }

    // MARK: - Unbounded Mode Tests

    static let unboundedModes: [EnterAmountView.Mode] = [
        .sell,
        .withdraw,
    ]

    @Test("Unbounded modes return nil for maxTransactionAmount", arguments: unboundedModes)
    func maxTransactionAmount_unboundedModes_returnsNil(mode: EnterAmountView.Mode) {
        let sendLimit = Self.sendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: mode,
            entryCurrency: .usd,
            sendLimitProvider: { _ in sendLimit }
        )

        #expect(calculator.maxTransactionAmount == nil)
    }

    @Test("Unbounded modes cap maxEnterAmount at balance only", arguments: unboundedModes)
    func maxEnterAmount_unboundedModes_returnsFullBalance(mode: EnterAmountView.Mode) {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000_000, convertedQuarks: 2_000_000_000)
        let sendLimit = Self.sendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: mode,
            entryCurrency: .usd,
            sendLimitProvider: { _ in sendLimit }
        )

        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }

    // MARK: - isWithinDisplayLimit Tests

    @Test func isWithinDisplayLimit_emptyAmount_returnsFalse() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "", max: max) == false)
    }

    @Test func isWithinDisplayLimit_zeroAmount_returnsFalse() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "0", max: max) == false)
    }

    @Test func isWithinDisplayLimit_invalidAmount_returnsFalse() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "abc", max: max) == false)
    }

    @Test func isWithinDisplayLimit_amountBelowMax_returnsTrue() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "0.50", max: max) == true)
    }

    @Test func isWithinDisplayLimit_amountEqualToMax_returnsTrue() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1.00", max: max) == true)
    }

    @Test func isWithinDisplayLimit_amountAboveMax_returnsFalse() {
        let max = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1.01", max: max) == false)
    }

    @Test("Amount matching the display-rounded max is allowed")
    func isWithinDisplayLimit_roundedDisplayBoundary_returnsTrue() {
        // 986700 quarks / 10^6 = 0.9867 USD, which formats as "$0.99" (halfUp)
        let max = Quarks(quarks: 986_700 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "0.99", max: max) == true)
    }

    @Test("Amount above the display-rounded max is rejected")
    func isWithinDisplayLimit_aboveRoundedDisplay_returnsFalse() {
        // 986700 quarks formats as "$0.99", so $1.00 should be rejected
        let max = Quarks(quarks: 986_700 as UInt64, currencyCode: .usd, decimals: 6)
        #expect(EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: "1.00", max: max) == false)
    }

    // MARK: - Max Enter Amount Tests

    @Test func maxEnterAmount_whenLimitIsNil_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return nil }
        )

        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }

    @Test func maxEnterAmount_whenBalanceLessThanLimit_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)
        let sendLimit = Self.sendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit }
        )

        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }

    @Test func maxEnterAmount_whenLimitLessThanBalance_returnsLimitDirectly() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000, convertedQuarks: 2_000_000)
        let sendLimit = Self.sendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit }
        )

        // No fx conversion: limit is returned as-is (server already localized).
        #expect(calculator.maxEnterAmount(maxBalance: balance) == sendLimit.maxPerTransaction)
    }

    @Test("maxEnterAmount for CAD user returns server-localized CAD limit, not a double conversion")
    func maxEnterAmount_giveMode_CAD_returnsLocalizedLimit() {
        // Balance: $500 CAD. Limit: $250 CAD (server already localized).
        let balance = Self.createExchangedFiat(
            underlyingQuarks: 500_000_000,
            convertedQuarks: 500_000_000,
            currency: .cad
        )
        let sendLimit = Self.sendLimit(
            nextTransaction: 250_000_000,
            maxPerTransaction: 250_000_000,
            maxPerDay: 1_385_574_951,
            currency: .cad
        )

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .cad,
            sendLimitProvider: { _ in return sendLimit }
        )

        // Must equal $250 CAD exactly, not ~$346 from fx double-multiplication.
        let result = calculator.maxEnterAmount(maxBalance: balance)
        #expect(result == sendLimit.maxPerTransaction)
        #expect(result.currencyCode == .cad)
    }

    @Test("maxEnterAmount for buy mode caps at maxPerDay, not maxPerTransaction")
    func maxEnterAmount_buyMode_capsAtMaxPerDay() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000, convertedQuarks: 2_000_000)
        // $0.10 remaining, $0.25 per-tx cap, $1.00 daily (used as buy per-tx)
        let sendLimit = Self.sendLimit(nextTransaction: 100_000, maxPerTransaction: 250_000, maxPerDay: 1_000_000)

        let calculator = EnterAmountCalculator(
            mode: .buy,
            entryCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit }
        )

        // Buy mode should use maxPerDay ($1.00), not maxPerTransaction ($0.25)
        #expect(calculator.maxEnterAmount(maxBalance: balance) == sendLimit.maxPerDay)
    }

}
