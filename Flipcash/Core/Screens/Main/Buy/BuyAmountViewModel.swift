//
//  BuyAmountViewModel.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@Observable
@MainActor
final class BuyAmountViewModel {
    var enteredAmount: String = ""

    @ObservationIgnored let mint: PublicKey
    @ObservationIgnored let currencyName: String

    /// Highest spendable balance among eligible payment sources — USDF plus
    /// displayable launchpad tokens, excluding the currency being bought.
    /// The keypad gate and the "Enter up to" subtitle both read this value.
    var maxPossibleAmount: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let eligible = session.balances(for: rate).filter { $0.stored.mint != mint }
        let zero = ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: rate, supplyQuarks: nil)
        return eligible.max { $0.exchangedFiat.nativeAmount.value < $1.exchangedFiat.nativeAmount.value }?.exchangedFiat ?? zero
    }

    /// True when no eligible source has a displayable value — the action
    /// button becomes an Add Money CTA.
    var isBalanceEmpty: Bool {
        !maxPossibleAmount.nativeAmount.hasDisplayableValue
    }

    var actionTitle: String {
        isBalanceEmpty ? "Add Money" : "Next"
    }

    var screenTitle: String { "Amount" }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self.mint = mint
        self.currencyName = currencyName
        self.session = session
        self.ratesController = ratesController
    }

    // MARK: - Actions

    func actionEnabled(_ entered: String) -> Bool {
        // One balances scan per call: the cap feeds both the empty check and
        // the display-limit gate (it's re-read on every keystroke).
        let cap = maxPossibleAmount.nativeAmount
        guard cap.hasDisplayableValue else { return true }
        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: entered,
            max: cap
        )
    }

    /// Next pushes the payment-currency step; with nothing to spend the same
    /// button routes to Add Money instead.
    func primaryAction(router: AppRouter) {
        if isBalanceEmpty {
            router.presentAddMoney(.buyCurrency, source: .buyShortfall)
            return
        }
        guard let entered = amountValidator.validate(enteredAmount) else { return }
        router.pushAny(BuyFlowPath.selectPaymentCurrency(
            targetMint: mint,
            targetName: currencyName,
            entered: FiatAmount(value: entered, currency: ratesController.balanceCurrency)
        ))
    }
}
