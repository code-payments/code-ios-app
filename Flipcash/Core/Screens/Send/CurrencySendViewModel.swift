//
//  CurrencySendViewModel.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// The amount step of sending one currency from its Currency Info page. The currency is fixed, so
/// there is no picker; the amount it collects is handed to the send (or the cash bill) that follows.
@Observable
final class CurrencySendViewModel {

    var enteredAmount: String = ""

    let mint: PublicKey

    private(set) var selectedBalance: ExchangedBalance?

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()

    init(sessionContainer: SessionContainer, mint: PublicKey) {
        self.mint = mint
        self.session = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
        self.selectedBalance = sessionContainer.ratesController.resolveInitialBalance(
            mint: mint,
            session: sessionContainer.session
        )
    }

    /// The keypad buffer parsed to a positive amount, or nil.
    private var validatedEntered: Decimal? {
        guard let amount = amountValidator.validate(enteredAmount), amount > 0 else { return nil }
        return amount
    }

    /// The entered amount in the currency it was typed in.
    var enteredTotal: FiatAmount? {
        validatedEntered.map { FiatAmount(value: $0, currency: ratesController.balanceCurrency) }
    }

    /// Next is off at zero and above the balance.
    var canContinue: Bool {
        guard let validatedEntered, let selectedBalance,
              let fiat = selectedBalance.enteredFiat(for: validatedEntered, rate: ratesController.rateForBalanceCurrency()),
              fiat.onChainAmount.quarks > 0 else { return false }
        if case .sufficient = session.hasSufficientFunds(for: fiat) { return true }
        return false
    }

    /// What's left to spend in this currency.
    var available: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        guard let balance = session.balance(for: mint) else {
            return ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: rate, supplyQuarks: nil)
        }
        return balance.computeExchangedValue(with: rate)
    }
}
