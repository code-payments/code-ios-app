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
//  Fix: negativeWithdrawableAmount now checks userFlags.withdrawalFeeAmount
//       for all mints, blocking the withdrawal before it reaches IntentWithdraw.
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
        // Fee comes from userFlags (1_000_000 quarks = $1.00)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 1_000_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000 // $10.00 balance
        ))
        viewModel.enteredAmount = "0.46" // $0.46 USDF
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        // Before fix: nil (guard passes → crash in IntentWithdraw)
        // After fix: non-nil (guard blocks → "Withdrawal Amount Too Small" dialog)
        #expect(viewModel.negativeWithdrawableAmount != nil)
    }

    @Test("negativeWithdrawableAmount is nil for USDF when fee is within amount")
    func negativeWithdrawableAmount_usdf_feeWithinAmount() {
        // Fee comes from userFlags (500_000 quarks = $0.50)
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 500_000)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000 // $10.00 balance
        ))
        viewModel.enteredAmount = "5.00" // $5.00 USDF
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        // Fee ($0.50) < amount ($5.00) — no problem, should be nil
        #expect(viewModel.negativeWithdrawableAmount == nil)
    }

    @Test("negativeWithdrawableAmount is nil for USDF when userFlags fee is zero")
    func negativeWithdrawableAmount_usdf_zeroFee() {
        // Zero fee in userFlags — no fee applies, never blocks
        let viewModel = WithdrawViewModelTestHelpers.createViewModel(withdrawalFeeQuarks: 0)
        viewModel.kind = .sameMint(WithdrawViewModelTestHelpers.createExchangedBalance(
            mint: .usdf,
            quarks: 10_000_000
        ))
        viewModel.enteredAmount = "0.46"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        // Zero fee — should always be nil
        #expect(viewModel.negativeWithdrawableAmount == nil)
    }
}
