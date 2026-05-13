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

    /// Helper to create a test view model with no mint (auto-select path).
    static func createViewModel() -> GiveViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock

        let viewModel = GiveViewModel(
            container: container,
            sessionContainer: sessionContainer,
            mint: nil
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
            imageURL: nil,
            costBasis: 0
        )
        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: quarks, mint: mint),
                rate: .oneToOne,
                supplyQuarks: effectiveSupplyQuarks
            )
        )
    }

    // MARK: - Initialization Tests

    @Test
    func testInitialization() {
        // Given/When: Creating a new view model with no balances and no mint
        let viewModel = Self.createViewModel()

        // Then: Initial state should be correct
        #expect(viewModel.enteredAmount == "")
        #expect(viewModel.actionState == .normal)
        #expect(viewModel.session.dialogItem == nil)
        #expect(viewModel.selectedBalance == nil)
        #expect(viewModel.canGive == false)
    }

    // MARK: - Currency Selection Sync Tests

    @Test("Selecting a currency syncs selectedBalance and ratesController")
    func testSelectCurrency_SyncsBalanceAndRatesController() {
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 1_000_000_000_000,
            supplyQuarks: 10_000 * 10_000_000_000
        )

        viewModel.selectCurrencyAction(exchangedBalance: balance)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(viewModel.ratesController.selectedTokenMint == .jeffy)
        #expect(viewModel.ratesController.isSelectedToken(.jeffy) == true)
    }

    @Test("Switching currency updates both selectedBalance and ratesController")
    func testSelectCurrency_SwitchingUpdatesSync() {
        let viewModel = Self.createViewModel()
        let firstBalance = Self.createExchangedBalance(
            mint: .jeffy,
            quarks: 1_000_000_000_000,
            supplyQuarks: 10_000 * 10_000_000_000
        )
        let secondBalance = Self.createExchangedBalance(
            mint: .usdf,
            quarks: 5_000_000
        )

        viewModel.selectCurrencyAction(exchangedBalance: firstBalance)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(viewModel.ratesController.selectedTokenMint == .jeffy)

        viewModel.selectCurrencyAction(exchangedBalance: secondBalance)

        #expect(viewModel.selectedBalance?.stored.mint == .usdf)
        #expect(viewModel.ratesController.selectedTokenMint == .usdf)
        #expect(viewModel.ratesController.isSelectedToken(.jeffy) == false)
    }

    @Test("Selecting a currency clears entered amount")
    func testSelectCurrency_ClearsEnteredAmount() {
        let viewModel = Self.createViewModel()
        let balance = Self.createExchangedBalance()
        viewModel.enteredAmount = "42.00"

        viewModel.selectCurrencyAction(exchangedBalance: balance)

        #expect(viewModel.enteredAmount == "")
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

    // MARK: - Init resolution Tests

    @Test("Init with no mint and a stored selection resolves to the stored mint")
    func testInit_NoMint_HonorsStoredSelection() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectToken(.jeffy)

        let viewModel = GiveViewModel(container: .mock, sessionContainer: container, mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("Init with no mint and no prior selection picks the highest-value giveable balance and persists it")
    func testInit_NoMint_PicksHighestAndPersists() throws {
        // Same supply for both mints (so per-token curve price is equal), but
        // Jeffy has 100× the holding in quarks → 100× the USDF-equivalent,
        // putting Jeffy first in the `usdf`-desc sort.
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 100_000 * 10_000_000_000),
                quarks: 10_000_000_000_000
            ),
            .init(
                mint: .makeLaunchpad(address: .usdcAuthority, supplyFromBonding: 100_000 * 10_000_000_000),
                quarks: 100_000_000_000
            ),
        ])
        container.ratesController.selectedTokenMint = nil

        let viewModel = GiveViewModel(container: .mock, sessionContainer: container, mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    @Test("Init with no mint and a stale sub-threshold selection falls back to the highest displayable balance")
    func testInit_NoMint_SubThresholdRememberedMint_FallsBackToHighest() throws {
        let staleHolding = SessionContainer.Holding(
            mint: .makeLaunchpad(
                address: .jeffy,
                supplyFromBonding: 10_000_000 * 10_000_000_000
            ),
            quarks: 100
        )
        let displayableHolding = SessionContainer.Holding(
            mint: .makeLaunchpad(
                address: .usdcAuthority,
                supplyFromBonding: 10_000 * 10_000_000_000
            ),
            quarks: 1_000_000_000_000
        )
        let container = try SessionContainer.makeTest(holdings: [
            staleHolding,
            displayableHolding,
        ])
        container.ratesController.selectToken(.jeffy)

        let viewModel = GiveViewModel(container: .mock, sessionContainer: container, mint: nil)

        #expect(viewModel.selectedBalance?.stored.mint == .usdcAuthority)
        #expect(container.ratesController.selectedTokenMint == .usdcAuthority)
    }

    @Test("Init with a mint resolves to that mint even if a different one is stored")
    func testInit_WithMint_OverridesStoredSelection() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(address: .jeffy, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
            .init(
                mint: .makeLaunchpad(address: .usdcAuthority, supplyFromBonding: 10_000 * 10_000_000_000),
                quarks: 1_000_000_000_000
            ),
        ])
        container.ratesController.selectToken(.usdcAuthority)

        let viewModel = GiveViewModel(container: .mock, sessionContainer: container, mint: .jeffy)

        #expect(viewModel.selectedBalance?.stored.mint == .jeffy)
        #expect(container.ratesController.selectedTokenMint == .jeffy)
    }

    // MARK: - Over-balance (insufficient funds)

    @Test("Over-balance bonded entry fires 'Short' dialog with a real shortfall")
    func giveAction_overBalanceBonded_firesShortDialogWithRealShortfall() throws {
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(
                    address: .jeffy,
                    supplyFromBonding: 1_000_000 * 10_000_000_000
                ),
                quarks: 10 * 10_000_000_000
            ),
        ])
        container.ratesController.selectToken(.jeffy)
        let viewModel = GiveViewModel(container: .mock, sessionContainer: container, mint: nil)

        let balance = try #require(viewModel.selectedBalance)
        // 100× the displayed balance — unambiguously over and may exceed curve TVL.
        let overAmount = balance.exchangedFiat.nativeAmount.value * 100
        viewModel.enteredAmount = "\(overAmount)"

        // Next must stay tappable so the dialog can fire on tap.
        #expect(viewModel.canGive == true)
        #expect(viewModel.session.dialogItem == nil)

        viewModel.giveAction()

        let dialog = try #require(viewModel.session.dialogItem)
        let title = try #require(dialog.title)

        // "You're $X Short" — not "You Need More Cash" and not "Transaction Limit Reached".
        #expect(title.hasPrefix("You're"))
        #expect(title.hasSuffix("Short"))
        // Previous bug rendered the amount as $0.00 — guard against regression.
        // The `$` anchor avoids a false positive on legitimate shortfalls
        // like "$10.00 Short", whose "0.00 Short" substring would otherwise
        // match.
        #expect(!title.contains("$0.00"))
    }
}
