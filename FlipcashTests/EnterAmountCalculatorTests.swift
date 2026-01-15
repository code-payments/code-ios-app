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
    
    // MARK: - Currency Tests
    
    @Test func currency_whenModeIsCurrency_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .cad,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .cad)
    }
    
    @Test func currency_whenModeIsBuy_returnsEntryCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .buy,
            entryCurrency: .eur,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .eur)
    }
    
    @Test func currency_whenModeIsOnramp_returnsOnrampCurrency() {
        let calculator = EnterAmountCalculator(
            mode: .onramp,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .gbp)
    }
    
    @Test func currency_whenModeIsWithdraw_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .withdraw,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .usd)
    }
    
    @Test func currency_whenModeIsWalletDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .walletDeposit("Phantom"),
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.currency == .usd)
    }
    
    @Test func currency_whenModeIsPhantomDeposit_returnsUSD() {
        let calculator = EnterAmountCalculator(
            mode: .phantomDeposit,
            entryCurrency: .cad,
            onrampCurrency: .gbp,
            transactionLimitProvider: { _ in return nil },
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
            transactionLimitProvider: { _ in return nil },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.maxTransactionAmount == 0)
    }
    
    @Test func maxTransactionAmount_whenLimitExists_returnsLimit() {
        let limit = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return limit },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.maxTransactionAmount == limit)
    }
    
    // MARK: - Max Enter Amount Tests
    
    @Test func maxEnterAmount_whenRateIsNil_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)
        let limit = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return limit },
            rateProvider: { _ in nil }
        )
        
        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }
    
    @Test func maxEnterAmount_whenBalanceLessThanLimit_returnsBalance() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 500_000, convertedQuarks: 500_000)
        let limit = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return limit },
            rateProvider: { _ in Rate.oneToOne }
        )
        
        #expect(calculator.maxEnterAmount(maxBalance: balance) == balance.converted)
    }
    
    @Test func maxEnterAmount_whenLimitLessThanBalance_returnsConvertedLimit() {
        let balance = Self.createExchangedFiat(underlyingQuarks: 2_000_000, convertedQuarks: 2_000_000)
        let limit = Quarks(quarks: 1_000_000 as UInt64, currencyCode: .usd, decimals: 6)
        
        let calculator = EnterAmountCalculator(
            mode: .currency,
            entryCurrency: .usd,
            onrampCurrency: .usd,
            transactionLimitProvider: { _ in return limit },
            rateProvider: { _ in Rate.oneToOne }
        )
        
        let result = calculator.maxEnterAmount(maxBalance: balance)
        let expectedLimit = limit.converting(to: Rate.oneToOne, decimals: PublicKey.usdf.mintDecimals)
        
        #expect(result == expectedLimit)
    }
}
