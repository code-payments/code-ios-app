//
//  Regression_6a0e1a1.swift
//  Flipcash
//
//  EXC_BREAKPOINT: ExchangedFiat.subtractingFee → TokenAmount.- traps when
//                  the pinned recompute of the withdraw amount lands below
//                  the fee. The amount-screen `isBelowMinimumWithdraw` gate
//                  uses the live rate; `prepareSubmission` recomputes
//                  against the pinned rate. Sufficient pinned-vs-live drift
//                  (severe for 0-decimal currencies) produces sub-fee
//                  quarks and trips the underflow precondition.
//
//  Fix:            Guard in WithdrawViewModel.completeWithdrawal after
//                  prepareSubmission — surfaces the existing
//                  "Withdrawal Amount Too Small" dialog instead of
//                  reaching IntentWithdraw / TokenAmount subtraction.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("Regression: 6a0e1a1 – withdraw traps when pinned amount falls below fee", .bug("6a0e1a1add5b5015cee68d6d"))
struct Regression_6a0e1a1 {

    @Test("USDF: pinned rate drift produces sub-fee quarks → too-small dialog, no trap")
    @MainActor
    func usdf_pinDriftBelowFee_surfacesTooSmallDialog() async throws {
        // Fee: 500_000 USDF quarks ($0.50).
        // Live rate: 1.0 EUR/USD. Pinned rate: 5.0 EUR/USD (worst-case drift
        // to force the recompute below the fee). User enters 1 EUR — passes
        // the live-rate minimum (€0.50 fee + €0.01 floor = €0.51; €1 > €0.51).
        // Pinned recompute: 1 EUR / 5.0 = $0.20 = 200_000 USDF quarks < 500_000 fee.
        let (container, usdf) = try WithdrawViewModelTestHelpers.makeUSDFFixture(
            quarks: 100_000_000,
            withdrawalFeeQuarks: 500_000
        )
        container.ratesController.configureTestRates(
            balanceCurrency: .eur,
            rates: [Rate(fx: 1.0, currency: .eur)]
        )
        await container.ratesController.verifiedProtoService.saveRates([
            .freshRate(currencyCode: "EUR", rate: 5.0)
        ])

        let viewModel = WithdrawViewModel(container: .mock, sessionContainer: container)
        viewModel.kind = .sameMint(usdf)
        viewModel.enteredAmount = "1"
        viewModel.destinationMetadata = WithdrawViewModelTestHelpers.createDestinationMetadata()

        await viewModel.completeWithdrawal()

        let dialog = try #require(viewModel.dialogItem)
        // Title from `WithdrawViewModel.showWithdrawalTooSmallError`.
        #expect(dialog.title == "Withdrawal Amount Too Small")
        #expect(viewModel.withdrawButtonState == .normal)
    }
}
