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
    
    /// Helper to create a test view model with CAD as the entry currency
    static func createViewModel() -> CurrencyBuyViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock
        
        // Set entry currency to CAD explicitly for deterministic tests
        sessionContainer.ratesController.entryCurrency = .cad
        
        // Insert CAD rate into the database
        let snapshot = RatesSnapshot(date: Date(), rates: [cadRate])
        try! sessionContainer.database.insert(snapshot: snapshot)
        
        return CurrencyBuyViewModel(
            currencyPublicKey: .usdc,
            container: container,
            sessionContainer: sessionContainer
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
    func testEnteredFiat_WithCADEntry_ConvertedIsCAD_UnderlyingIsUSD() throws {
        // Given: A view model with 1 CAD entered
        // Rate is 1.35 (1 USD = 1.35 CAD), so 1 CAD = ~0.74 USD underlying
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "1"
        
        // When: Getting the enteredFiat from the viewModel
        let exchangedFiat = try #require(viewModel.enteredFiat)
        
        // Then: Converted should be in CAD (the entry currency)
        #expect(exchangedFiat.converted.currencyCode == .cad)
        
        // Then: Underlying should be in USD (the base currency)
        #expect(exchangedFiat.underlying.currencyCode == .usd)
        
        // Then: Rate should match our configured CAD rate
        #expect(exchangedFiat.rate.currency == .cad)
        #expect(exchangedFiat.rate.fx == Self.cadRate.fx)
        
        // Then: The underlying USD value should be less than converted CAD value
        // because 1 CAD < 1 USD (1 CAD ≈ 0.74 USD at 1.35 rate)
        #expect(exchangedFiat.underlying.quarks < exchangedFiat.converted.quarks)
    }
    
    // MARK: - Reset Tests -
    
    @Test
    func testReset_ClearsEnteredAmount() {
        // Given: View model with entered amount
        let viewModel = Self.createViewModel()
        viewModel.enteredAmount = "100"
        
        // When: Resetting
        viewModel.reset()
        
        // Then: Amount should be cleared and enteredFiat should be nil
        #expect(viewModel.enteredAmount == "")
        #expect(viewModel.enteredFiat == nil)
    }
}
