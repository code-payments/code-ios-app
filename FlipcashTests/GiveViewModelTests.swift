//
//  GiveViewModelTests.swift
//  FlipcashTests
//
//  Created by Claude on 2025-11-13.
//

import Foundation
import Testing
import SwiftUI
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite(.serialized)
struct GiveViewModelTests {

    // MARK: - Test Helpers

    /// Helper to create a test view model
    static func createViewModel() -> GiveViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock

        let viewModel = GiveViewModel(
            container: container,
            sessionContainer: sessionContainer
        )

        return viewModel
    }

    /// Helper to create ExchangedBalance
    static func createExchangedBalance(
        mint: PublicKey = .usdc,
        quarks: UInt64 = 1_000_000,
        tvl: UInt64? = nil
    ) -> ExchangedBalance {
        // For non-USDC tokens, TVL is required by StoredBalance
        // For USDC, TVL should be nil
        let effectiveTVL: UInt64?
        let effectiveSellFeeBps: Int?

        if mint == .usdc {
            effectiveTVL = nil
            effectiveSellFeeBps = nil
        } else {
            // Non-USDC tokens must have TVL
            // Use $1M default - low TVL causes issues with discrete bonding curve
            effectiveTVL = tvl ?? 1_000_000_000_000 // Default to $1M TVL
            effectiveSellFeeBps = 0
        }

        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: mint == .usdc ? "USDC" : "TOKEN",
            name: mint == .usdc ? "USD Coin" : "Test Token",
            supplyFromBonding: nil,
            coreMintLocked: effectiveTVL,
            sellFeeBps: effectiveSellFeeBps,
            mint: mint,
            vmAuthority: mint == .usdc ? nil : .usdcAuthority,
            updatedAt: Date(),
            imageURL: nil
        )
        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: mint,
                rate: .oneToOne,
                tvl: effectiveTVL
            )
        )
    }

    // MARK: - Initialization Tests

    @Test
    func testInitialization() {
        // Given/When: Creating a new view model
        let viewModel = Self.createViewModel()

        // Then: Initial state should be correct
        #expect(viewModel.enteredAmount == "")
        #expect(viewModel.actionState == .normal)
        #expect(viewModel.dialogItem == nil)
        #expect(viewModel.selectedBalance == nil)
        #expect(viewModel.canGive == false)
    }

    // MARK: - canGive Tests

    @Test
    func testCanGive_EmptyAmount_ReturnsFalse() {
        // Given: View model with no amount entered
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = ""

        // When/Then: canGive should be false
        #expect(viewModel.canGive == false)
    }

    @Test
    func testCanGive_InvalidAmount_ReturnsFalse() {
        // Given: View model with invalid amount
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "invalid"

        // When/Then: canGive should be false
        #expect(viewModel.canGive == false)
    }

    @Test
    func testCanGive_ZeroAmount_ReturnsFalse() {
        // Given: View model with zero amount
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "0"

        // When/Then: canGive should be false
        #expect(viewModel.canGive == false)
    }

    @Test
    func testCanGive_NoSelectedBalance_ReturnsFalse() {
        // Given: View model with amount but no selected balance
        let viewModel = Self.createViewModel()
        // Don't select any balance
        viewModel.enteredAmount = "10"

        // When/Then: canGive should be false
        #expect(viewModel.canGive == false)
    }

    @Test
    func testCanGive_ValidAmountAndBalance_ReturnsTrue() {
        // Given: View model with valid amount and balance
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "10"

        // When/Then: canGive should be true
        #expect(viewModel.canGive == true)
    }

    // MARK: - selectCurrencyAction Tests

    @Test
    func testSelectCurrencyAction_SetsBalanceAndClearsAmount() {
        // Given: View model with some entered amount
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "100"
        let balance = Self.createExchangedBalance()

        // When: Selecting a currency
        viewModel.selectCurrencyAction(exchangedBalance: balance)

        // Then: Balance should be set, amount cleared, and navigation updated
        #expect(viewModel.selectedBalance != nil)
        #expect(viewModel.enteredAmount == "")
    }

    // MARK: - enteredFiat Calculation Tests (USDC)

    @Test
    func testEnteredFiat_USDC_CalculatesCorrectly() {
        // Given: View model with USDC balance
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdc,
            quarks: 100_000_000
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "10.50"

        // When: enteredFiat is computed
        // Access through canGive which uses enteredFiat internally
        let canGive = viewModel.canGive

        // Then: Should be able to give (meaning enteredFiat computed successfully)
        #expect(canGive == true)
    }

    // MARK: - enteredFiat Calculation Tests (Bonded Tokens)

    @Test
    func testEnteredFiat_BondedToken_CalculatesCorrectly() {
        // Given: View model with bonded token
        // TVL $1M supports ~100,000 tokens at discrete curve prices
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdcAuthority,
            quarks: 1_000_000_000_000, // 100 tokens (10 decimals)
            tvl: 1_000_000_000_000 // $1M TVL
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "0.50"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give
        #expect(canGive == true)
    }

    @Test
    func testEnteredFiat_BondedToken_AmountAtMaxBalance() {
        // Given: View model with bonded token where user has significant balance
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdcAuthority,
            quarks: 5_000_000_000_000, // 500 tokens (10 decimals)
            tvl: 10_000_000_000_000 // $10M TVL
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "5.00"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give (amount is within balance value)
        #expect(canGive == true)
    }

    @Test
    func testEnteredFiat_BondedToken_LargeTVL() {
        // Given: View model with realistic TVL ($100M)
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdcAuthority,
            quarks: 10_000_000_000_000, // 1,000 tokens
            tvl: 100_000_000_000_000 // $100M TVL
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "25.00"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give
        #expect(canGive == true)
    }

    // MARK: - Edge Cases

    @Test
    func testEnteredAmount_NegativeValue_CanGiveFalse() {
        // Given: View model with negative amount
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "-10"

        // When/Then: canGive should be false
        #expect(viewModel.canGive == false)
    }

    @Test
    func testEnteredAmount_VeryLargeValue_HandledCorrectly() {
        // Given: View model with very large amount
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(quarks: UInt64.max)
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "999999999.99"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should handle large values
        #expect(canGive == true)
    }

    @Test
    func testEnteredAmount_DecimalPlaces_HandledCorrectly() {
        // Given: View model with many decimal places
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "10.123456789"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should handle decimal values
        #expect(canGive == true)
    }

    // MARK: - Bonding Curve TVL Boundary Tests
    // Note: TVL-exceeded tests are covered at the DiscreteBondingCurve unit test level (test 12.14).
    // These integration tests verify the successful path through GiveViewModel.

    @Test
    func testEnteredFiat_BondedToken_ModestTVL_SmallAmount_Succeeds() {
        // Given: View model with bonded token and modest TVL
        // TVL is $10K, user tries to exchange $100 (valid)
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdcAuthority,
            quarks: 10_000_000_000_000, // 1,000 tokens
            tvl: 10_000_000_000 // $10K TVL
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "100.00"  // $100 < $10K TVL

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give (amount within TVL)
        #expect(canGive == true, "Should allow exchange amount within TVL")
    }

    @Test
    func testEnteredFiat_BondedToken_AmountWellUnderTVL_Succeeds() {
        // Given: View model where entered amount is well under TVL
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .usdcAuthority,
            quarks: 100_000_000_000_000,
            tvl: 10_000_000_000_000 // $10M TVL
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "500.00"  // $500 << $10M TVL

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give
        #expect(canGive == true, "Should allow exchange amount well under TVL")
    }
}
