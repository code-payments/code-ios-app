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
@testable import FlipcashCore
@testable import Flipcash

@MainActor
struct CurrencySellConfirmationViewModelTests {

    // MARK: - Test Helpers -

    /// USD→CAD rate of 1.35 — native (CAD) is derived as `usdValue * 1.35`.
    static let testRate = Rate(fx: 1.35, currency: .cad)

    static func makeFreshPinnedState() -> VerifiedState {
        VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date()
        )
    }

    static func makeStalePinnedState() -> VerifiedState {
        VerifiedState.makeForTest(
            rateTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1),
            reserveTimestamp: Date().addingTimeInterval(-VerifiedState.clientMaxAge - 1)
        )
    }

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
        amount: ExchangedFiat? = nil,
        pinnedState: VerifiedState? = nil
    ) -> CurrencySellConfirmationViewModel {
        let exchangedFiat = amount ?? createExchangedFiat(mint: mint)
        return CurrencySellConfirmationViewModel(
            mint: mint,
            amount: exchangedFiat,
            pinnedState: pinnedState ?? makeFreshPinnedState()
        )
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

    @Test
    func testFee_BondedMint_ScalesNativeProportionally() {
        // Given: A bonded-mint amount of 5 whole Jeffy at $13.50 CAD native.
        // Construct directly to bypass the curve (which would need supply).
        let amount = ExchangedFiat(
            onChainAmount: TokenAmount(quarks: 50_000_000_000, mint: .jeffy), // 5 Jeffy at 10 decimals
            nativeAmount: FiatAmount(value: Decimal(string: "13.50")!, currency: .cad),
            currencyRate: Self.testRate
        )
        let viewModel = Self.createViewModel(mint: .jeffy, amount: amount)

        // When: Getting fee
        let fee = viewModel.fee

        // Then: On-chain side: 50_000_000_000 * 100 / 10_000 = 500_000_000 Jeffy quarks
        #expect(fee.onChainAmount.quarks == 500_000_000)
        #expect(fee.onChainAmount.mint == .jeffy)
        // Native side: scaled by the exact on-chain ratio (500M / 50B = 0.01).
        // 13.50 CAD * 0.01 = 0.135 CAD
        #expect(fee.nativeAmount.value == Decimal(string: "0.135")!)
        #expect(fee.nativeAmount.currency == .cad)
    }

    @Test
    func testFeeFormatted_ZeroOnChainFee_DropsTildePrefix() {
        // Given: Amount small enough that 1% on-chain rounds to 0 quarks.
        // The fee is literally zero — display should be $0.00, NOT ~$0.00.
        let amount = Self.createExchangedFiat(onChainQuarks: 50)
        let viewModel = Self.createViewModel(amount: amount)

        // When: Formatting the fee
        let formatted = viewModel.feeFormatted

        // Then: No tilde — fee is exactly zero, not approximately zero.
        #expect(!formatted.contains("~"))
    }

    @Test
    func testFeeFormatted_NonZeroButSubCentFee_KeepsTildePrefix() {
        // Given: On-chain fee is 1+ quarks (non-zero) but converts to a
        // sub-cent native amount (e.g. 100 USDF quarks → 1 quark fee → tiny CAD).
        // This is the "~$0.00" display case — the fee *exists*, just below
        // the currency's display precision.
        let amount = Self.createExchangedFiat(onChainQuarks: 100)
        let viewModel = Self.createViewModel(amount: amount)

        // When: Formatting the fee
        let formatted = viewModel.feeFormatted

        // Then: Tilde present — non-zero but approximately zero.
        #expect(formatted.contains("~"))
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

    // MARK: - Pinned State Tests -

    @Test("canPerformAction is false when pinnedState is stale")
    func canPerformAction_stalePinnedState_returnsFalse() {
        let viewModel = Self.createViewModel(pinnedState: Self.makeStalePinnedState())

        #expect(viewModel.canPerformAction == false)
    }

    @Test("canPerformAction is true when pinnedState is fresh")
    func canPerformAction_freshPinnedState_returnsTrue() {
        let viewModel = Self.createViewModel(pinnedState: Self.makeFreshPinnedState())

        #expect(viewModel.canPerformAction == true)
    }

    @Test("pinnedState with both rate and reserve timestamps is treated as bonded-sell fresh state")
    func canPerformAction_freshBondedPinnedState_returnsTrue() {
        // Sell is bonded-only; both protos should be present. Both timestamps fresh.
        let pinnedState = VerifiedState.makeForTest(
            rateTimestamp: Date(),
            reserveTimestamp: Date()
        )
        let viewModel = Self.createViewModel(pinnedState: pinnedState)

        #expect(viewModel.canPerformAction == true)
    }
}
