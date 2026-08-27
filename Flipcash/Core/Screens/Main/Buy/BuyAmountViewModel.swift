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
    /// The selected payment source ("Buy with"). Defaults to Dollars when held,
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

    var screenTitle: String {
        BuyFlowTitle.forCurrency(mint, session: session, ratesController: ratesController)
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()
    /// Double-tap guard around the async pin fetch.
    private var isSubmitting = false

    init(
        mint: PublicKey,
        currencyName: String,
        session: Session,
        ratesController: RatesController
    ) {
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
        correctEntryToAffordable()
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

    /// The fee the selected payment source charges, and whether it lands *on
    /// top* of the entry rather than being skimmed out of it.
    ///
    /// A token-funded buy pays the pool's sell fee out of the sale, so the debit
    /// is the entry grossed up; a Dollars buy adds a flat 1% on top.
    private var paymentFee: (bps: UInt64, chargedOnTop: Bool) {
        guard let selected = session.balance(for: paymentMint) else { return (0, false) }
        guard selected.mint == .usdf else {
            return (UInt64(max(0, selected.sellFeeBps ?? 100)), false)
        }
        return (100, true)
    }

    /// Drops the entry to the most the payment balance can fund once its fee is
    /// applied, when the entry as typed would overrun it.
    ///
    /// Entry is capped at the raw balance while the fee comes out of that same
    /// balance, so entering the maximum always overruns — by the fee, and never
    /// by more. That band is narrow enough to correct silently, and correcting
    /// here rather than on the confirmation keeps the entry and the receipt
    /// showing the same figure.
    func correctEntryToAffordable() {
        guard let entered = amountValidator.validate(enteredAmount) else { return }

        let balance = maxPossibleAmount.nativeAmount
        let fee = paymentFee
        guard let corrected = entryAffordableAfterFee(
            entered: entered,
            balance: balance,
            feeBps: fee.bps,
            feeChargedOnTop: fee.chargedOnTop
        ) else { return }

        enteredAmount = amountValidator.string(
            from: corrected.value,
            fractionDigits: balance.currency.maximumFractionDigits
        )
    }

    /// Converts the entered (net) target fiat into the payment token's gross
    /// debit against the pinned rate + supply. Moved here from the old
    /// payment-currency step now that selection is inline.
    ///
    /// Internal (not private) so the payment-compute tests can exercise the real
    /// production path directly.
    func computePaymentAmount(for balance: StoredBalance, entered: FiatAmount, pin: VerifiedState) -> ExchangedFiat? {
        let entered = FiatAmount(value: entered.value, currency: pin.rate.currency)

        if balance.mint == .usdf {
            // No fee on the USDF path: buying from reserves has no on-chain fee
            // to collect, so the debit equals the entered target — grossing it up
            // would just make the user over-buy. Within the displayed balance the
            // compute is balance-capped so FX display rounding can't push the
            // quarks past the spendable reserves; past it it stays uncapped so
            // the summary shows what was actually entered and the confirmation's
            // gate can surface the shortfall.
            let displayedBalance = balance.usdf.converting(to: pin.rate).value
                .rounded(to: entered.currency.maximumFractionDigits)
            let isWithinDisplayedBalance = entered.value <= displayedBalance
            return ExchangedFiat.compute(
                fromEntered: entered,
                rate: pin.rate,
                mint: .usdf,
                supplyQuarks: 0, // unused on the USDF path
                balance: isWithinDisplayedBalance ? session.balance(for: .usdf)?.usdf : nil
            )
        }

        guard let supply = pin.supplyFromBonding else { return nil }

        // Deliberately uncapped: the entry has already been corrected to what the
        // balance can fund, so any remaining overrun is a real shortfall the
        // confirmation's gate must surface rather than something to clamp away.
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
