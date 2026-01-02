//
//  CurrencySellConfirmationViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2025-12-30.
//

import Foundation
import Testing
import SwiftUI
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
struct CurrencySellConfirmationViewModelTests {
    
    // MARK: - Test Helpers -
    
    /// Helper to create ExchangedFiat for testing
    /// Uses USD→CAD rate of 1.35 to demonstrate underlying vs converted relationship
    static let testRate = Rate(fx: 1.35, currency: .cad)
    
    static func createExchangedFiat(
        underlyingQuarks: UInt64 = 10_000_000_000_000,  // 10,000 USD (9 decimals)
        convertedQuarks: UInt64 = 13_500_000_000,       // 13,500 CAD (6 decimals) = 10,000 * 1.35
        mint: PublicKey = .usdc
    ) -> ExchangedFiat {
        let underlying = Quarks(quarks: underlyingQuarks, currencyCode: .usd, decimals: 9)
        let converted = Quarks(quarks: convertedQuarks, currencyCode: .cad, decimals: 6)
        
        return ExchangedFiat(
            underlying: underlying,
            converted: converted,
            rate: testRate,
            mint: mint
        )
    }
    
    /// Helper to create a test view model
    static func createViewModel(
        mint: PublicKey = .usdc,
        amount: ExchangedFiat? = nil
    ) -> CurrencySellConfirmationViewModel {
        let exchangedFiat = amount ?? createExchangedFiat(mint: mint)
        return CurrencySellConfirmationViewModel(mint: mint, amount: exchangedFiat)
    }
    
    // MARK: - Initialization Tests -
    
    @Test
    func testInitialization_DefaultValues() {
        // Given/When: Creating a new view model
        let viewModel = Self.createViewModel()
        
        // Then: Initial state should be correct
        #expect(viewModel.actionButtonState == .normal)
        #expect(viewModel.dialogItem == nil)
        #expect(viewModel.canDismissSheet == false)
    }
    
    // MARK: - Fee Calculation Tests -
    
    @Test
    func testFee_CalculatesOnePercent() {
        // Given: Amount of 10,000 USD / 13,500 CAD
        let amount = Self.createExchangedFiat(
            underlyingQuarks: 10_000_000_000_000,  // 10,000 USD
            convertedQuarks: 13_500_000_000        // 13,500 CAD
        )
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting fee
        let fee = viewModel.fee
        
        // Then: Fee should be 1% (100 bps)
        // 13_500_000_000 * 100 / 10_000 = 135_000_000 (135 CAD)
        #expect(fee.converted.quarks == 135_000_000)
        // 10_000_000_000_000 * 100 / 10_000 = 100_000_000_000 (100 USD)
        #expect(fee.underlying.quarks == 100_000_000_000)
    }
    
    @Test
    func testFee_LargeAmount_CalculatesCorrectly() {
        // Given: Large amount - 1,000,000 USD = 1,350,000 CAD at 1.35 rate
        let amount = Self.createExchangedFiat(
            underlyingQuarks: 1_000_000_000_000_000,   // 1,000,000 USD (9 decimals)
            convertedQuarks: 1_350_000_000_000         // 1,350,000 CAD (6 decimals)
        )
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting fee
        let fee = viewModel.fee
        
        // Then: Fee should be 1%
        #expect(fee.converted.quarks == 13_500_000_000)  // 13,500 CAD
        #expect(fee.underlying.quarks == 10_000_000_000_000)  // 10,000 USD
    }
    
    @Test
    func testFee_SmallAmount_RoundsDown() {
        // Given: Small amount where 1% would be fractional
        // 50 quarks * 100 / 10_000 = 0 (integer division rounds down)
        let amount = Self.createExchangedFiat(
            underlyingQuarks: 50,
            convertedQuarks: 50
        )
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting fee
        let fee = viewModel.fee
        
        // Then: Fee rounds down to 0
        #expect(fee.converted.quarks == 0)
        #expect(fee.underlying.quarks == 0)
    }
    
    @Test
    func testFee_PreservesCurrencyMetadata() {
        // Given: Amount with specific currency codes
        let amount = Self.createExchangedFiat()
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting fee
        let fee = viewModel.fee
        
        // Then: Currency metadata should be preserved
        #expect(fee.underlying.currencyCode == amount.underlying.currencyCode)
        #expect(fee.converted.currencyCode == amount.converted.currencyCode)
        #expect(fee.rate.currency == amount.rate.currency)
        #expect(fee.mint == amount.mint)
    }
    
    // MARK: - Amount After Fee Tests -
    
    @Test
    func testAmountAfterFee_SubtractsFeeCorrectly() {
        // Given: Amount of 10,000 USD (underlying) = 13,500 CAD (converted) at 1.35 rate
        let amount = Self.createExchangedFiat(
            underlyingQuarks: 10_000_000_000_000,  // 10,000 USD
            convertedQuarks: 13_500_000_000        // 13,500 CAD
        )
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting amount after fee
        let afterFee = viewModel.amountAfterFee
        
        // Then: Should be original minus 1% fee
        // Underlying: 10,000,000,000,000 - 100,000,000,000 = 9,900,000,000,000 (9,900 USD)
        #expect(afterFee.underlying.quarks == 9_900_000_000_000)
        // Converted is recalculated: 9,900 USD * 1.35 = 13,365 CAD = 13,365,000,000 quarks
        #expect(afterFee.converted.quarks == 13_365_000_000)
    }
        
    // MARK: - Sheet Dismissal Tests -
        
    @Test
    func testCanDismissSheet_FalseAlways() {
        // Given: View model
        let viewModel = Self.createViewModel()
        
        // Then: Should prevent dismissal
        #expect(viewModel.canDismissSheet == false)
    }
    
    
    // MARK: - Button State Tests -
    
    @Test
    func testActionButtonState_InitiallyNormal() {
        // Given/When: Fresh view model
        let viewModel = Self.createViewModel()
        
        // Then: Should be normal
        #expect(viewModel.actionButtonState == .normal)
    }
        
    // MARK: - Dialog State Tests -
    
    @Test
    func testDialogItem_InitiallyNil() {
        // Given/When: Fresh view model
        let viewModel = Self.createViewModel()
        
        // Then: Should have no dialog
        #expect(viewModel.dialogItem == nil)
    }
    
    @Test
    func testDialogItem_CanBeSet() {
        // Given: View model
        let viewModel = Self.createViewModel()
        
        // When: Setting a dialog
        viewModel.dialogItem = .init(
            style: .success,
            title: "Test",
            subtitle: "Test subtitle",
            dismissable: false
        ) {
            .okay(kind: .standard) {}
        }
        
        // Then: Should have dialog
        #expect(viewModel.dialogItem != nil)
        #expect(viewModel.dialogItem?.title == "Test")
    }
    
    // MARK: - Edge Cases -
    
    @Test
    func testFee_MaxUInt64_DoesNotOverflow() {
        // Given: Very large but safe amount (avoiding overflow in multiplication)
        // Max safe: UInt64.max / 100 to avoid overflow
        let safeMax = UInt64.max / 100
        let amount = Self.createExchangedFiat(
            underlyingQuarks: safeMax,
            convertedQuarks: safeMax
        )
        let viewModel = Self.createViewModel(amount: amount)
        
        // When: Getting fee
        let fee = viewModel.fee
        
        // Then: Should calculate without overflow
        let expectedFee = safeMax * 100 / 10_000
        #expect(fee.converted.quarks == expectedFee)
    }
    
    @Test
    func testAmountAfterFee_PreservesMint() {
        // Given: Amount with specific mint
        let mint = PublicKey.usdc
        let viewModel = Self.createViewModel(mint: mint)
        
        // When: Getting amount after fee
        let afterFee = viewModel.amountAfterFee
        
        // Then: Mint should be preserved
        #expect(afterFee.mint == mint)
    }
}
