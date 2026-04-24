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

    @Test("Regression: returns nil (no crash) when fee exceeds entered amount")
    func withdrawableAmount_feeExceedsEntered_returnsNil() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance()
        viewModel.enteredAmount = "0.50"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 1_000_000, mint: .usdf)
        )

        #expect(viewModel.withdrawableAmount == nil)
    }

    @Test("Regression: bonded-mint negative delta is a USD value, not a raw token count")
    func negativeWithdrawableAmount_bondedMint_isUSDDelta() throws {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createBondedBalance()
        viewModel.enteredAmount = "0.50"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 1_000_000, mint: .usdf)
        )

        let delta = try #require(viewModel.negativeWithdrawableAmount)

        // Overflow above $1 USD means token count is leaking through as a fiat value.
        #expect(delta.currency == .usd)
        #expect(delta.value > 0)
        #expect(delta.value <= Decimal(1))
    }

    // MARK: - canProceedToAddress

    @Test("Over-balance bonded entry disables Next via canProceedToAddress")
    func canProceedToAddress_overBalanceBonded_isFalse() throws {
        let (viewModel, balance) = try makeBondedSetup()
        let balanceValue = balance.exchangedFiat.nativeAmount.value

        viewModel.enteredAmount = "\(balanceValue * 100)"

        // enteredFiat stays non-nil so EnterAmountView's isExceedingLimit can
        // flip the subtitle red.
        #expect(viewModel.enteredFiat != nil)
        #expect(viewModel.canProceedToAddress == false)
    }

    @Test("At-or-below balance leaves canProceedToAddress enabled")
    func canProceedToAddress_withinBalanceBonded_isTrue() throws {
        let (viewModel, balance) = try makeBondedSetup()
        let balanceValue = balance.exchangedFiat.nativeAmount.value

        viewModel.enteredAmount = "\(balanceValue / 10)"

        #expect(viewModel.canProceedToAddress == true)
    }

    // MARK: - Helpers

    /// Builds a `WithdrawViewModel` backed by an in-memory session whose
    /// `session.balance(for:)` is populated, so `maxWithdrawLimit` returns a
    /// real cap rather than zero.
    private func makeBondedSetup() throws -> (WithdrawViewModel, ExchangedBalance) {
        let mint: PublicKey = .jeffy
        let container = try SessionContainer.makeTest(holdings: [
            .init(
                mint: .makeLaunchpad(
                    address: mint,
                    supplyFromBonding: 1_000_000 * 10_000_000_000
                ),
                quarks: 10 * 10_000_000_000
            ),
        ])
        let stored = try #require(container.session.balance(for: mint))
        let rate = container.ratesController.rateForEntryCurrency()
        let balance = ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: rate)
        )
        let viewModel = WithdrawViewModel(
            isPresented: .constant(true),
            container: .mock,
            sessionContainer: container
        )
        viewModel.selectedBalance = balance
        return (viewModel, balance)
    }

    // MARK: - canCompleteWithdrawal / Pinned State

    @Test("canCompleteWithdrawal is false when pinnedState is nil")
    func canCompleteWithdrawal_noPinnedState_returnsFalse() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(pinnedState: nil)
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000)
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.canCompleteWithdrawal == false)
    }

    @Test("canCompleteWithdrawal is false when pinnedState is stale")
    func canCompleteWithdrawal_stalePinnedState_returnsFalse() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(pinnedState: .stale(bonded: false))
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(quarks: 10_000_000)
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.canCompleteWithdrawal == false)
    }

    @Test("canCompleteWithdrawal is true when pinnedState is fresh and all fields valid")
    func canCompleteWithdrawal_freshPinnedState_returnsTrue() throws {
        let fresh = VerifiedState.fresh(bonded: false)
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: MintMetadata.usdf, quarks: 10_000_000)
        ])
        let balance = try #require(container.session.balance(for: .usdf))
        let rate = container.ratesController.rateForEntryCurrency()
        let exchangedBalance = ExchangedBalance(
            stored: balance,
            exchangedFiat: balance.computeExchangedValue(with: rate)
        )

        let viewModel = WithdrawViewModel(
            isPresented: .constant(true),
            container: .mock,
            sessionContainer: container
        )
        viewModel.pinnedState = fresh
        viewModel.selectedBalance = exchangedBalance
        viewModel.enteredAmount = "5.00"
        viewModel.enteredAddress = "11111111111111111111111111111111"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        #expect(viewModel.canCompleteWithdrawal == true)
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
