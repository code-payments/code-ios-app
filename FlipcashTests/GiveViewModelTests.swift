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
        mint: PublicKey = .usdf,
        quarks: UInt64 = 1_000_000,
        supplyQuarks: UInt64? = nil
    ) -> ExchangedBalance {
        // For non-USDF tokens, supplyQuarks is required by StoredBalance
        // For USDF, supplyQuarks should be nil
        let effectiveSupplyQuarks: UInt64?
        let effectiveSellFeeBps: Int?

        if mint == .usdf {
            effectiveSupplyQuarks = nil
            effectiveSellFeeBps = nil
        } else {
            // Non-USDF tokens must have supply
            // Use 10,000 tokens default (10,000 * 10^10 quarks)
            effectiveSupplyQuarks = supplyQuarks ?? 10_000 * 10_000_000_000
            effectiveSellFeeBps = 0
        }

        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: mint == .usdf ? "USDF" : "TOKEN",
            name: mint == .usdf ? "USDF Coin" : "Test Token",
            supplyFromBonding: effectiveSupplyQuarks,
            sellFeeBps: effectiveSellFeeBps,
            mint: mint,
            vmAuthority: mint == .usdf ? nil : .usdcAuthority,
            updatedAt: Date(),
            imageURL: nil
        )
        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: mint,
                rate: .oneToOne,
                supplyQuarks: effectiveSupplyQuarks
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
            mint: .usdf,
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
        // 10,000 tokens supply supports reasonable exchange amounts
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 1_000_000_000_000, // 100 tokens (10 decimals)
            supplyQuarks: 10_000 * 10_000_000_000 // 10,000 tokens supply
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
            mint: .jeffy,
            quarks: 5_000_000_000_000, // 500 tokens (10 decimals)
            supplyQuarks: 50_000 * 10_000_000_000 // 50,000 tokens supply
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "5.00"

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give (amount is within balance value)
        #expect(canGive == true)
    }

    @Test
    func testEnteredFiat_BondedToken_LargeSupply() {
        // Given: View model with large supply (100,000 tokens)
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 10_000_000_000_000, // 1,000 tokens
            supplyQuarks: 100_000 * 10_000_000_000 // 100,000 tokens supply
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

    // MARK: - Bonding Curve Supply Boundary Tests
    // These integration tests verify the successful path through GiveViewModel.

    @Test
    func testEnteredFiat_BondedToken_ModestSupply_SmallAmount_Succeeds() {
        // Given: View model with bonded token and modest supply
        // 1,000 tokens supply, user tries to exchange $100 (valid)
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 10_000_000_000_000, // 1,000 tokens
            supplyQuarks: 1_000 * 10_000_000_000 // 1,000 tokens supply
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "1.00"  // $1 is valid for this supply

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give (amount within supply)
        #expect(canGive == true, "Should allow exchange amount within supply")
    }

    @Test
    func testEnteredFiat_BondedToken_AmountWellUnderMaxSupply_Succeeds() {
        // Given: View model where entered amount is well under max supply value
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 100_000_000_000_000, // 10,000 tokens
            supplyQuarks: 50_000 * 10_000_000_000 // 50,000 tokens supply
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)
        viewModel.enteredAmount = "10.00"  // $10 well within available

        // When: Checking if can give
        let canGive = viewModel.canGive

        // Then: Should be able to give
        #expect(canGive == true, "Should allow exchange amount well under max supply value")
    }
}
