//
//  CurrencyBuyViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-01-02.
//

import Foundation
import Testing
import SwiftUI
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

@MainActor
struct CurrencyBuyViewModelTests {

    // MARK: - Test Helpers -

    /// CAD rate: 1 USD = 1.35 CAD
    static let cadRate = Rate(fx: 1.35, currency: .cad)

    /// Default pinned state matching `cadRate` — the VM now sources its rate
    /// from `pinnedState.rate` (not the live cache), so the pinned proof and
    /// the configured live rate MUST agree for tests that aren't specifically
    /// exercising a pinned-vs-live divergence.
    static let cadPinnedState = VerifiedState.fresh(
        bonded: false,
        currencyCode: "CAD",
        exchangeRate: 1.35
    )

    /// Helper to create a test view model with CAD as the entry currency and a fresh pinned state.
    /// Uses the mock SessionContainer which has no seeded balance.
    static func createViewModel(pinnedState: VerifiedState? = nil) -> CurrencyBuyViewModel {
        let sessionContainer = SessionContainer.mock

        // Configure entry currency and inject the CAD rate for deterministic tests
        sessionContainer.ratesController.configureTestRates(entryCurrency: .cad, rates: [cadRate])

        return CurrencyBuyViewModel(
            currencyPublicKey: .usdf,
            currencyName: "USDF",
            pinnedState: pinnedState ?? cadPinnedState,
            session: sessionContainer.session
        )
    }

    /// Helper to create a view model backed by a real database seeded with USDF balance,
    /// so `canPerformAction` can reach the display-limit check.
    static func createViewModelWithBalance(pinnedState: VerifiedState? = nil) throws -> CurrencyBuyViewModel {
        // 10 USDF (10_000_000 quarks at 6 decimals)
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: MintMetadata.usdf, quarks: 10_000_000)
        ])

        container.ratesController.configureTestRates(entryCurrency: .cad, rates: [cadRate])

        return CurrencyBuyViewModel(
            currencyPublicKey: .jeffy,
            currencyName: "Test",
            pinnedState: pinnedState ?? cadPinnedState,
            session: container.session
        )
    }

    // MARK: - Initialization Tests -

    @Test
    func testInitialization_DefaultValues() {
        // Given/When: Creating a new view model
        let viewModel = Self.createViewModel()

        // Then: Initial state should be correct
        #expect(viewModel.actionButtonState == .normal)
        #expect(viewModel.enteredAmount == "")
        #expect(viewModel.dialogItem == nil)
        #expect(viewModel.canPerformAction == false)
    }

    // MARK: - Entered Fiat Direction Tests -

    @Test
    func testEnteredFiat_WithCADEntry_NativeIsCAD_USDFValueIsUSD() throws {
        // Given: A view model with 1 CAD entered
        // Rate is 1.35 (1 USD = 1.35 CAD), so 1 CAD = ~0.74 USD usdf value
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "1"

        // When: Getting the enteredFiat from the viewModel
        let exchangedFiat = try #require(viewModel.enteredFiat)

        // Then: Native should be in CAD (the entry currency)
        #expect(exchangedFiat.nativeAmount.currency == .cad)

        // Then: USDF value should be in USD (the base currency)
        #expect(exchangedFiat.usdfValue.currency == .usd)

        // Then: Rate should match our configured CAD rate
        #expect(exchangedFiat.currencyRate.currency == .cad)
        #expect(exchangedFiat.currencyRate.fx == Self.cadRate.fx)

        // Then: The USD value should be less than the native CAD value
        // because 1 CAD < 1 USD (1 CAD ≈ 0.74 USD at 1.35 rate)
        #expect(exchangedFiat.usdfValue.value < exchangedFiat.nativeAmount.value)
    }

    // MARK: - Pinned State Tests -

    @Test("canPerformAction is false when pinnedState is stale, even with a valid amount entered")
    func canPerformAction_stalePinnedState_returnsFalse() {
        let viewModel = Self.createViewModel(pinnedState: .stale(bonded: false))
        viewModel.enteredAmount = "1"

        #expect(viewModel.canPerformAction == false)
    }

    @Test("canPerformAction is true when pinnedState is fresh and a valid amount is entered")
    func canPerformAction_freshPinnedState_returnsTrue() throws {
        let viewModel = try Self.createViewModelWithBalance(pinnedState: .fresh(bonded: false))
        viewModel.enteredAmount = "1"

        #expect(viewModel.canPerformAction == true)
    }

}
