//
//  Regression_6900e1760283b4eb88e9674a.swift
//  Flipcash
//
//  Crash: ExchangedFiat.subtracting(fee:) throws feeLargerThanAmount
//         when USDF withdrawal fee exceeds a small entered amount.
//         The ViewModel guard only covered bonded tokens, allowing USDF
//         withdrawals to reach IntentWithdraw without fee validation.
//
//  Fix: the amount-entry gate (isBelowMinimumWithdraw) now applies for
//       all mints, blocking the withdrawal before it reaches IntentWithdraw.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: 6900e17 – feeLargerThanAmount crash on USDF withdrawal", .bug("6900e1760283b4eb88e9674a"))
struct Regression_6900e17 {

    @Test("USDF below the fee surfaces the dialog and never advances toward IntentWithdraw")
    func usdf_belowFee_showsDialogAndBlocksAdvance() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000, // $100 balance
            withdrawalFeeQuarks: 1_000_000 // $1.00 fee
        )
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.pushSubstep = { pushed.append($0) }
        viewModel.kind = .sameMint(usdf)
        viewModel.enteredAmount = "0.46" // below the $1.00 fee
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        viewModel.amountEnteredAction()

        // Before fix: gate didn't fire → user reached IntentWithdraw → crash.
        // After fix: gate fires → dialog shown, no navigation.
        #expect(viewModel.dialogItem?.title == "Withdrawal Amount Too Small")
        #expect(pushed.isEmpty)
    }

    @Test("USDF above the fee advances to the address screen")
    func usdf_aboveFee_advances() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000, // $100 balance
            withdrawalFeeQuarks: 500_000 // $0.50 fee
        )
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.pushSubstep = { pushed.append($0) }
        viewModel.kind = .sameMint(usdf)
        viewModel.enteredAmount = "5.00"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        viewModel.amountEnteredAction()

        #expect(viewModel.dialogItem == nil)
        #expect(pushed == [.enterAddress])
    }

    @Test("USDF with a zero fee advances regardless of amount")
    func usdf_zeroFee_advances() throws {
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 0
        )
        var pushed: [WithdrawNavigationPath] = []
        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.pushSubstep = { pushed.append($0) }
        viewModel.kind = .sameMint(usdf)
        viewModel.enteredAmount = "0.46"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        viewModel.amountEnteredAction()

        #expect(viewModel.dialogItem == nil)
        #expect(pushed == [.enterAddress])
    }
}
