//
//  BuyAmountViewModel.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.buy-amount")

@Observable
@MainActor
final class BuyAmountViewModel {
    var enteredAmount: String = ""
    var dialogItem: DialogItem?
    /// The selected payment source ("Get with"). Defaults to Dollars when held,
    /// otherwise the largest eligible balance.
    var paymentMint: PublicKey

    @ObservationIgnored let mint: PublicKey
    @ObservationIgnored let currencyName: String

    /// Eligible payment sources: held, displayable, excluding the currency being
    /// bought (the server rejects same-mint swaps). Read by the picker sheet.
    var paymentOptions: [ExchangedBalance] {
        let rate = ratesController.rateForBalanceCurrency()
        return session.balances(for: rate).filter { balance in
            balance.stored.mint != mint && balance.exchangedFiat.hasDisplayableValue()
        }
    }

    /// The selected payment source's balance — the entry cap and the "Enter up
    /// to" subtitle both read this value.
    var maxPossibleAmount: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        if let selected = session.balance(for: paymentMint) {
            return selected.exchanged(with: rate).exchangedFiat
        }
        return ExchangedFiat.compute(onChainAmount: .zero(mint: .usdf), rate: rate, supplyQuarks: nil)
    }

    /// Display name of the selected payment source — "Dollars" for USDF.
    var paymentName: String { session.balance(for: paymentMint)?.name ?? "Dollars" }

    /// Logo of the selected payment source, from the held-balance cache.
    var paymentImageURL: URL? { session.balance(for: paymentMint)?.imageURL }

    /// True when nothing is spendable — the action button becomes an Add Money CTA.
    var isBalanceEmpty: Bool { paymentOptions.isEmpty }

    var actionTitle: String {
        isBalanceEmpty ? "Add Money" : "Next"
    }

    var screenTitle: String { "Get" }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()
    /// Double-tap guard around the async pin fetch.
    private var isSubmitting = false

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self.mint = mint
        self.currencyName = currencyName
        self.session = session
        self.ratesController = ratesController

        // Default the payment source to Dollars when it's spendable, otherwise
        // the largest eligible balance — so Next is never dead on arrival.
        let rate = ratesController.rateForBalanceCurrency()
        let options = session.balances(for: rate).filter { $0.stored.mint != mint && $0.exchangedFiat.hasDisplayableValue() }
        if options.contains(where: { $0.stored.mint == .usdf }) {
            self.paymentMint = .usdf
        } else if let largest = options.max(by: { $0.exchangedFiat.nativeAmount.value < $1.exchangedFiat.nativeAmount.value }) {
            self.paymentMint = largest.stored.mint
        } else {
            self.paymentMint = .usdf
        }
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

    /// Next computes the payment debit for the selected source and pushes the
    /// summary directly; with nothing to spend the same button routes to Add
    /// Money instead.
    func primaryAction(router: AppRouter) {
        if isBalanceEmpty {
            router.presentAddMoney(.buyCurrency, source: .buyShortfall)
            return
        }
        guard let entered = amountValidator.validate(enteredAmount) else { return }
        guard !isSubmitting else { return }
        isSubmitting = true

        Task {
            defer { isSubmitting = false }

            guard let selected = session.balance(for: paymentMint) else { return }
            guard let pin = await ratesController.currentPinnedState(for: ratesController.balanceCurrency, mint: paymentMint) else {
                logger.warning("No pinned state for payment mint", metadata: [
                    "paymentMint": "\(paymentMint.base58)",
                ])
                showRateUnavailable()
                return
            }
            guard let paymentAmount = computePaymentAmount(
                for: selected,
                entered: FiatAmount(value: entered, currency: ratesController.balanceCurrency),
                pin: pin
            ) else {
                showRateUnavailable()
                return
            }

            router.pushAny(BuyFlowPath.paymentConfirmation(
                targetMint: mint,
                targetName: currencyName,
                payment: selected,
                paymentAmount: paymentAmount,
                pinnedState: pin
            ))
        }
    }

    /// Converts the entered (net) target fiat into the payment token's gross
    /// debit against the pinned rate + supply. Moved here from the old
    /// payment-currency step now that selection is inline.
    private func computePaymentAmount(for balance: StoredBalance, entered: FiatAmount, pin: VerifiedState) -> ExchangedFiat? {
        let entered = FiatAmount(value: entered.value, currency: pin.rate.currency)

        if balance.mint == .usdf {
            // New UI charges the same 1% conversion fee on Dollars-funded buys,
            // so the debit is grossed up over the entered target; legacy pays
            // exactly the entered amount. Within the displayed balance the
            // compute is balance-capped so FX display rounding can't push the
            // quarks past the spendable reserves; past it it's deliberately
            // uncapped so the confirmation's gate can offer Buy Maximum instead
            // of silently shrinking the entry.
            let debit = BetaFlags.shared.hasEnabled(.newUI)
                ? entered.grossingUpLaunchpadSellFee(bps: UInt64(max(0, balance.sellFeeBps ?? 100)))
                : entered
            let displayedBalance = balance.usdf.converting(to: pin.rate).value
                .rounded(to: entered.currency.maximumFractionDigits)
            let isWithinDisplayedBalance = debit.value <= displayedBalance
            return ExchangedFiat.compute(
                fromEntered: debit,
                rate: pin.rate,
                mint: .usdf,
                supplyQuarks: 0, // unused on the USDF path
                balance: isWithinDisplayedBalance ? session.balance(for: .usdf)?.usdf : nil
            )
        }

        guard let supply = pin.supplyFromBonding else { return nil }

        // Deliberately uncapped: when the fee doesn't fit, the gross must exceed
        // the balance so the confirmation's gate can offer Buy Maximum explicitly
        // instead of silently clamping.
        let gross = entered.grossingUpLaunchpadSellFee(bps: UInt64(max(0, balance.sellFeeBps ?? 100)))
        return ExchangedFiat.compute(
            fromEntered: gross,
            rate: pin.rate,
            mint: balance.mint,
            supplyQuarks: supply
        )
    }

    // MARK: - Dialogs

    private func showRateUnavailable() {
        dialogItem = .error(title: "Rate Unavailable", subtitle: "Couldn't get a fresh rate. Please try again.")
    }
}
