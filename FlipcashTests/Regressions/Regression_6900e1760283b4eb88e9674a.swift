//
//  Regression_6900e1760283b4eb88e9674a.swift
//  Flipcash
//
//  Crash: ExchangedFiat.subtracting(fee:) throws feeLargerThanAmount
//         when USDF withdrawal fee exceeds a small entered amount.
//         The ViewModel guard (negativeWithdrawableAmount) only covered
//         bonded tokens, allowing USDF withdrawals to reach IntentWithdraw
//         without fee validation.
//
//  Fix: negativeWithdrawableAmount now falls back to destinationMetadata.fee
//       for USDF, blocking the withdrawal before it reaches IntentWithdraw.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6900e17 – feeLargerThanAmount crash on USDF withdrawal", .bug("6900e1760283b4eb88e9674a"))
struct Regression_6900e17 {

    @Test("negativeWithdrawableAmount is non-nil for USDF when fee exceeds amount")
    func negativeWithdrawableAmount_usdf_feeExceedsAmount() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000 // $10.00 balance
        )
        viewModel.enteredAmount = "0.46" // ~462,922 quarks ($0.46 USDC)
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 1_000_000, mint: .usdf) // $1.00 fee
        )

        // Before fix: nil (guard passes → crash in IntentWithdraw)
        // After fix: non-nil (guard blocks → "Withdrawal Amount Too Small" dialog)
        #expect(viewModel.negativeWithdrawableAmount != nil)
    }

    @Test("negativeWithdrawableAmount is nil for USDF when fee is within amount")
    func negativeWithdrawableAmount_usdf_feeWithinAmount() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000 // $10.00 balance
        )
        viewModel.enteredAmount = "5.00" // $5.00 USDC
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: true,
            fee: TokenAmount(quarks: 500_000, mint: .usdf) // $0.50 fee
        )

        // Fee ($0.50) < amount ($5.00) — no problem, should be nil
        #expect(viewModel.negativeWithdrawableAmount == nil)
    }

    @Test("negativeWithdrawableAmount is nil for USDF when no initialization required")
    func negativeWithdrawableAmount_usdf_noInitialization() {
        let viewModel = WithdrawViewModelTestHelpers.createViewModel()
        viewModel.selectedBalance = WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000
        )
        viewModel.enteredAmount = "0.46"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata(
            requiresInitialization: false,
            fee: TokenAmount(quarks: 0, mint: .usdf)
        )

        // No initialization fee — should always be nil
        #expect(viewModel.negativeWithdrawableAmount == nil)
    }
}
