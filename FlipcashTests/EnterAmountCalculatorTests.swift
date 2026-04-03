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

    static let testRate = Rate(fx: 1, currency: .usd)

    static func createExchangedFiat(
        underlyingQuarks: UInt64,
        convertedQuarks: UInt64
    ) -> ExchangedFiat {
        let underlying = Quarks(quarks: underlyingQuarks, currencyCode: .usd, decimals: 6)
        let converted = Quarks(quarks: convertedQuarks, currencyCode: .usd, decimals: 6)

        return ExchangedFiat(
            underlying: underlying,
            converted: converted,
            rate: testRate,
            mint: .usdf
        )
    }

    static func usdSendLimit(nextTransaction: UInt64, maxPerTransaction: UInt64, maxPerDay: UInt64) -> SendLimit {
        SendLimit(
            nextTransaction: Quarks(quarks: nextTransaction, currencyCode: .usd, decimals: 6),
            maxPerTransaction: Quarks(quarks: maxPerTransaction, currencyCode: .usd, decimals: 6),
            maxPerDay: Quarks(quarks: maxPerDay, currencyCode: .usd, decimals: 6)
        )
    }
    
    // MARK: - Currency Tests
    
    @Test func currency_whenModeIsCurrency_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .cad,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .cad)
    }
    
    @Test func currency_whenModeIsBuy_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .buy,
            entryCurrency: .eur,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .eur)
    }
    
    @Test func currency_whenModeIsOnramp_returnsOnrampCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .onramp,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .gbp)
    }
    
    @Test func currency_whenModeIsWithdraw_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .withdraw,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )

        #expect(calculator.currency == .cad)
    }
    
    @Test func currency_whenModeIsWalletDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .walletDeposit("Phantom"),
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .usd)
    }
    
    @Test func currency_whenModeIsPhantomDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .phantomDeposit,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .usd)
    }
    
    // MARK: - Max Transaction Amount Tests

    @Test func maxTransactionAmount_whenLimitIsNil_returnsZero() {
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )

        #expect(calculator.maxTransactionAmount == 0)
    }

    @Test func maxTransactionAmount_whenLimitExists_returnsLimit() {
        let sendLimit = Self.usdSendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit },
            rateProvider: { _ in nil }
        )

        // Give mode: min(maxPerTransaction, nextTransaction) = $1.00
        #expect(calculator.maxTransactionAmount == sendLimit.maxPerTransaction)
    }

    // MARK: - Give Mode Limit Tests

    @Test("Give mode uses min(maxPerTransaction, nextTransaction) when daily partially used")
    func maxTransactionAmount_giveMode_partiallyUsedDaily_usesNextTransaction() {
        // $100 remaining, $250 per-tx cap, $1000 daily
        let sendLimit = Self.usdSendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in sendLimit },
            rateProvider: { _ in nil }
        )

        // nextTransaction ($100) < maxPerTransaction ($250), so effective limit is $100
        #expect(calculator.maxTransactionAmount == sendLimit.nextTransaction)
    }

    @Test("Give mode on fresh day uses maxPerTransaction when nextTransaction equals it")
    func maxTransactionAmount_giveMode_freshDay_usesMaxPerTransaction() {
        // Fresh day: nextTransaction == maxPerTransaction ($250)
        let sendLimit = Self.usdSendLimit(nextTransaction: 250_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in sendLimit },
            rateProvider: { _ in nil }
        )

        #expect(calculator.maxTransactionAmount == sendLimit.maxPerTransaction)
    }

    // MARK: - Buy Mode Limit Tests

    static let buyModes: [EnterAmountView.Mode] = [.buy, .phantomDeposit, .walletDeposit("Phantom"), .onramp]

    @Test("Buy-type modes use maxPerDay as per-transaction limit", arguments: buyModes)
    func maxTransactionAmount_buyModes_usesMaxPerDay(mode: EnterAmountView.Mode) {
        let sendLimit = Self.usdSendLimit(nextTransaction: 100_000_000, maxPerTransaction: 250_000_000, maxPerDay: 1_000_000_000)

        let calculator = EnterAmountCalculator(
            mode: mode,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in sendLimit },
            rateProvider: { _ in nil }
        )

        #expect(calculator.maxTransactionAmount == sendLimit.maxPerDay)
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
    
    @Test func maxEnterAmount_whenRateIsNil_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)
        let sendLimit = Self.usdSendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit },
            rateProvider: { _ in nil }
        )

        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }

    @Test func maxEnterAmount_whenBalanceLessThanLimit_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)
        let sendLimit = Self.usdSendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit },
            rateProvider: { _ in Rate.oneToOne }
        )

        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }

    @Test func maxEnterAmount_whenLimitLessThanBalance_returnsConvertedLimit() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000, convertedQuarks: 2_000_000)
        let sendLimit = Self.usdSendLimit(nextTransaction: 1_000_000, maxPerTransaction: 1_000_000, maxPerDay: 5_000_000)

        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit },
            rateProvider: { _ in Rate.oneToOne }
        )

        let result = calculator.maxEnterAmount(maxBalance: balance)
        let expectedLimit = sendLimit.maxPerTransaction.converting(to: Rate.oneToOne, decimals: PublicKey.usdf.mintDecimals)

        #expect(result == expectedLimit)
    }

    @Test("maxEnterAmount for buy mode caps at maxPerDay, not maxPerTransaction")
    func maxEnterAmount_buyMode_capsAtMaxPerDay() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000, convertedQuarks: 2_000_000)
        // $0.10 remaining, $0.25 per-tx cap, $1.00 daily (used as buy per-tx)
        let sendLimit = Self.usdSendLimit(nextTransaction: 100_000, maxPerTransaction: 250_000, maxPerDay: 1_000_000)

        let calculator = EnterAmountCalculator(
            mode: .buy,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            sendLimitProvider: { _ in return sendLimit },
            rateProvider: { _ in Rate.oneToOne }
        )

        let result = calculator.maxEnterAmount(maxBalance: balance)
        let expectedLimit = sendLimit.maxPerDay.converting(to: Rate.oneToOne, decimals: PublicKey.usdf.mintDecimals)

        // Buy mode should use maxPerDay ($1.00), not maxPerTransaction ($0.25)
        #expect(result == expectedLimit)
    }

}
