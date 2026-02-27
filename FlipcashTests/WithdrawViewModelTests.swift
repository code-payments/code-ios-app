//
//  WithdrawViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-02-27.
//

import Foundation
import Testing
import SwiftUI
import FlipcashCore
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

// MARK: - Test Helpers

@MainActor
private enum TestHelpers {

    static func createViewModel(
        entryCurrency: CurrencyCode = .usd,
        rates: [Rate] = [.oneToOne]
    ) -> WithdrawViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock

        sessionContainer.ratesController.configureTestRates(
            entryCurrency: entryCurrency,
            rates: rates
        )

        return WithdrawViewModel(
            isPresented: .constant(true),
            container: container,
            sessionContainer: sessionContainer
        )
    }

    static func createExchangedBalance(
        mint: PublicKey = .usdf,
        quarks: UInt64 = 10_000_000
    ) -> ExchangedBalance {
        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: mint,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )

        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: mint,
                rate: .oneToOne,
                supplyQuarks: nil
            )
        )
    }

    static func createDestinationMetadata(
        requiresInitialization: Bool = false,
        fee: Quarks = Quarks(quarks: 0 as UInt64, currencyCode: .usd, decimals: 6)
    ) -> DestinationMetadata {
        DestinationMetadata(
            kind: .token,
            destination: try! PublicKey(base58: "11111111111111111111111111111111"),
            mint: .usdf,
            isValid: true,
            requiresInitialization: requiresInitialization,
            fee: fee
        )
    }
}

// MARK: - Tests

@MainActor
@Suite("WithdrawViewModel")
struct WithdrawViewModelTests {

    @Test("Non-USD rate computes correct underlying from entered amount")
    func enteredFiat_cadRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let viewModel = TestHelpers.createViewModel(entryCurrency: .cad, rates: [cadRate])
        viewModel.selectedBalance = TestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "7.00" // $7 CAD

        let fiat = viewModel.enteredFiat
        #expect(fiat?.rate.currency == .cad)
        // $7 CAD / 1.4 = $5 USD underlying
        #expect(fiat?.underlying.quarks == 5_000_000)
    }

    @Test("Subtracts fee from underlying when initialization required")
    func withdrawableAmount_withFee() {
        let viewModel = TestHelpers.createViewModel()
        viewModel.selectedBalance = TestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = TestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: Quarks(quarks: 500_000 as UInt64, currencyCode: .usd, decimals: 6)
        )

        // $5.00 - $0.50 = $4.50
        #expect(viewModel.withdrawableAmount?.underlying.quarks == 4_500_000)
    }

    @Test("Non-USD rate: subtracts fee in USD and recomputes converted")
    func withdrawableAmount_withFeeAndCADRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let viewModel = TestHelpers.createViewModel(entryCurrency: .cad, rates: [cadRate])
        viewModel.selectedBalance = TestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "7.00" // $7 CAD = $5 USD
        viewModel.destinationMetadata = TestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: Quarks(quarks: 500_000 as UInt64, currencyCode: .usd, decimals: 6)
        )

        let result = viewModel.withdrawableAmount

        // $5 USD - $0.50 USD = $4.50 USD underlying
        #expect(result?.underlying.quarks == 4_500_000)
        // $4.50 USD * 1.4 = $6.30 CAD converted
        #expect(result?.rate.currency == .cad)
        #expect(result?.converted.quarks == 6_300_000)

        // Display fee: $7.00 CAD − $6.30 CAD = $0.70 CAD
        #expect(viewModel.displayFee?.quarks == 700_000)
    }
}
