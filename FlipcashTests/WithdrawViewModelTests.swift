//
//  WithdrawViewModelTests.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-02-27.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("WithdrawViewModel")
struct WithdrawViewModelTests {

    @Test("Non-USD rate computes correct on-chain amount from entered amount")
    func enteredFiat_cadRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(entryCurrency: .cad, rates: [cadRate])
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "7.00" // $7 CAD

        let fiat = viewModel.enteredFiat
        #expect(fiat?.currencyRate.currency == .cad)
        // $7 CAD / 1.4 = $5 USDF → 5_000_000 quarks (6 decimals)
        #expect(fiat?.onChainAmount.quarks == 5_000_000)
    }

    @Test("Subtracts fee from on-chain amount when initialization required")
    func withdrawableAmount_withFee() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 500_000, mint: .usdf)
        )

        // $5.00 - $0.50 = $4.50
        #expect(viewModel.withdrawableAmount?.onChainAmount.quarks == 4_500_000)
    }

    @Test("Non-USD rate: subtracts fee in USD and recomputes native amount")
    func withdrawableAmount_withFeeAndCADRate() {
        let cadRate = Rate(fx: 1.4, currency: .cad)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(entryCurrency: .cad, rates: [cadRate])
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "7.00" // $7 CAD = $5 USD
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 500_000, mint: .usdf)
        )

        let result = viewModel.withdrawableAmount

        // $5 USD - $0.50 USD = $4.50 USD on-chain
        #expect(result?.onChainAmount.quarks == 4_500_000)
        // $4.50 USD * 1.4 = $6.30 CAD native
        #expect(result?.currencyRate.currency == .cad)
        #expect(result?.nativeAmount.value == Decimal(string: "6.30"))

        // Display fee: $7.00 CAD − $6.30 CAD = $0.70 CAD
        #expect(viewModel.displayFee?.value == Decimal(string: "0.70"))
    }
}
