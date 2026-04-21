//
//  Regression_give_max_precision.swift
//  Flipcash
//
//  Invariant: typing the displayed max on a newly-minted currency through
//  the Give flow must not disable the Next button. Same root cause as the
//  sell-max regression; `GiveViewModel.enteredFiat` had to start passing
//  the `balance:` cap to `ExchangedFiat.computeFromEntered`.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Regression: give-max precision (newly-minted bonding-curve balance)", .serialized)
struct Regression_give_max_precision {

    @Test(
        "Giving the displayed max on a newly-minted currency does not disable Next",
        arguments: Regression_sell_max_precision.sampledSupplies
    )
    func canGive_atDisplayedMax_returnsTrue(tokens: Int) throws {
        let supply = UInt64(tokens) * UInt64(DiscreteBondingCurve.quarksPerToken)

        let viewModel = GiveViewModelTests.createViewModel()
        let balance = GiveViewModelTests.createExchangedBalance(
            mint: .jeffy,
            quarks: supply,
            supplyQuarks: supply
        )
        viewModel.selectCurrencyAction(exchangedBalance: balance)

        // What the keypad sends after the user taps the displayed max.
        let displayedMaxString = balance.exchangedFiat.nativeAmount.formatted()
        let parser = NumberFormatter.fiat(
            currency: balance.exchangedFiat.nativeAmount.currency,
            minimumFractionDigits: balance.exchangedFiat.nativeAmount.currency.maximumFractionDigits
        )
        let typedAmountDecimal = try #require(parser.number(from: displayedMaxString)?.decimalValue)
        viewModel.enteredAmount = "\(typedAmountDecimal)"

        #expect(viewModel.canGive == true)
    }
}
