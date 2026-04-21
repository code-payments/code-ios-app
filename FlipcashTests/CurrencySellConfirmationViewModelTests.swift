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

    /// USD→CAD rate of 1.35 — native (CAD) is derived as `usdValue * 1.35`.
    static let testRate = Rate(fx: 1.35, currency: .cad)

    /// Helper to create ExchangedFiat for testing. USDF-minted fixtures bypass
    /// the bonding curve so `onChainAmount.quarks` equals `usdfValue.value * 10^6`
    /// and `nativeAmount.value` equals `usdfValue.value * rate.fx`.
    ///
    /// - Parameter onChainQuarks: raw token-native integer going into
    ///   `onChainAmount.quarks`. For USDF this is 6-decimal USD quarks; for a
    ///   bonded mint this is 10-decimal token quarks.
    static func createExchangedFiat(
        onChainQuarks: UInt64 = 10_000_000_000,         // 10,000 USDF (6 decimals)
        mint: PublicKey = .usdf
    ) -> ExchangedFiat {
        ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: onChainQuarks, mint: mint),
            rate: testRate,
            supplyQuarks: nil
        )
    }
    
    /// Helper to create a test view model
    static func createViewModel(
        mint: PublicKey = .usdf,
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
        // Given: 10,000 USDF on-chain. 1% fee → 100 USDF.
        let amount = Self.createExchangedFiat(
            onChainQuarks: 10_000_000_000  // 10,000 USDF (6 decimals)
        )
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: Fee token-native math: 10_000_000_000 * 100 / 10_000 = 100_000_000 quarks
        #expect(fee.onChainAmount.quarks == 100_000_000)
        // USDF bypasses the bonding curve, so usdfValue == onChainAmount.decimalValue.
        #expect(fee.usdfValue.value == 100)
        // Native at rate 1.35 CAD/USD: 100 * 1.35 = 135 CAD
        #expect(fee.nativeAmount.value == 135)
    }

    @Test
    func testFee_LargeAmount_CalculatesCorrectly() {
        // Given: 1,000,000 USDF on-chain. 1% fee → 10,000 USDF.
        let amount = Self.createExchangedFiat(
            onChainQuarks: 1_000_000_000_000   // 1,000,000 USDF (6 decimals)
        )
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: 1% fee in raw token quarks.
        #expect(fee.onChainAmount.quarks == 10_000_000_000)    // 10,000 USDF
        #expect(fee.usdfValue.value == 10_000)
        #expect(fee.nativeAmount.value == 13_500)              // 10,000 * 1.35 CAD
    }

    @Test
    func testFee_SmallAmount_RoundsDown() {
        // Given: Small amount where 1% would be fractional.
        // 50 quarks * 100 / 10_000 = 0 (integer division rounds down)
        let amount = Self.createExchangedFiat(onChainQuarks: 50)
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: Fee rounds down to 0 quarks.
        #expect(fee.onChainAmount.quarks == 0)
        #expect(fee.usdfValue.value == 0)
        #expect(fee.nativeAmount.value == 0)
    }

    @Test
    func testFee_PreservesCurrencyMetadata() {
        // Given: Amount with specific currency / mint.
        let amount = Self.createExchangedFiat()
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: Currency / rate / mint should be preserved through compute().
        #expect(fee.nativeAmount.currency == amount.nativeAmount.currency)
        #expect(fee.currencyRate.currency == amount.currencyRate.currency)
        #expect(fee.mint == amount.mint)
    }

    // MARK: - Amount After Fee Tests -

    @Test
    func testAmountAfterFee_SubtractsFeeCorrectly() {
        // Given: 10,000 USDF on-chain, 1% fee → 9,900 USDF remaining.
        let amount = Self.createExchangedFiat(
            onChainQuarks: 10_000_000_000
        )
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting amount after fee
        let afterFee = viewModel.amountAfterFee

        // Then: 10_000_000_000 - 100_000_000 = 9_900_000_000 quarks (9,900 USDF)
        #expect(afterFee.onChainAmount.quarks == 9_900_000_000)
        #expect(afterFee.usdfValue.value == 9_900)
        // 9,900 * 1.35 = 13,365 CAD
        #expect(afterFee.nativeAmount.value == 13_365)
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
        let amount = Self.createExchangedFiat(onChainQuarks: safeMax)
        let viewModel = Self.createViewModel(amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: Should calculate without overflow
        let expectedFee = safeMax * 100 / 10_000
        #expect(fee.onChainAmount.quarks == expectedFee)
    }
    
    @Test
    func testAmountAfterFee_PreservesMint() {
        // Given: Amount with specific mint
        let mint = PublicKey.usdf
        let viewModel = Self.createViewModel(mint: mint)
        
        // When: Getting amount after fee
        let afterFee = viewModel.amountAfterFee
        
        // Then: Mint should be preserved
        #expect(afterFee.mint == mint)
    }
}
