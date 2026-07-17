//
//  BuyPaymentCurrencyViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.buy-payment-currency")

@Observable
@MainActor
final class BuyPaymentCurrencyViewModel {

    var dialogItem: DialogItem?

    @ObservationIgnored let targetMint: PublicKey
    @ObservationIgnored let targetName: String
    @ObservationIgnored let entered: FiatAmount

    /// Spendable payment sources: the currency being bought is excluded (the
    /// server rejects same-mint swaps) and so are zero-value balances — a
    /// $0.00 source has no maximum to buy. Underfunded balances stay listed
    /// and tappable; their Buy surfaces the insufficient sheet offering the
    /// maximum amount instead.
    var rows: [ExchangedBalance] {
        let rate = ratesController.rateForBalanceCurrency()
        return session.balances(for: rate).filter { balance in
            balance.stored.mint != targetMint && balance.exchangedFiat.hasDisplayableValue()
        }
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    /// Double-tap guard around the async pin fetch.
    private var isSelecting = false

    init(targetMint: PublicKey, targetName: String, entered: FiatAmount, session: Session, ratesController: RatesController) {
        self.targetMint = targetMint
        self.targetName = targetName
        self.entered = entered
        self.session = session
        self.ratesController = ratesController
    }

    // MARK: - Selection

    func select(_ balance: ExchangedBalance, router: AppRouter) async {
        guard !isSelecting else { return }
        isSelecting = true
        defer { isSelecting = false }

        guard let pin = await ratesController.currentPinnedState(for: entered.currency, mint: balance.stored.mint) else {
            logger.warning("No pinned state for payment mint", metadata: [
                "paymentMint": "\(balance.stored.mint.base58)",
                "currency": "\(entered.currency.rawValue)",
            ])
            showRateUnavailable()
            return
        }
        guard let paymentAmount = computePaymentAmount(for: balance.stored, pin: pin) else {
            logger.warning("Payment amount compute failed", metadata: [
                "paymentMint": "\(balance.stored.mint.base58)",
                "entered": "\(entered.formatted())",
                "hasSupply": "\(pin.supplyFromBonding != nil)",
            ])
            showRateUnavailable()
            return
        }

        router.pushAny(BuyFlowPath.paymentConfirmation(
            targetMint: targetMint,
            targetName: targetName,
            payment: balance.stored,
            paymentAmount: paymentAmount,
            pinnedState: pin
        ))
    }

    /// Converts the entered (net) fiat into the payment token's gross debit
    /// against the pinned rate + supply.
    func computePaymentAmount(for balance: StoredBalance, pin: VerifiedState) -> ExchangedFiat? {
        let entered = FiatAmount(value: entered.value, currency: pin.rate.currency)

        if balance.mint == .usdf {
            // No fee on the USDF path. Within the displayed balance the
            // compute is balance-capped so FX display rounding can't push the
            // quarks past the spendable reserves; past it the compute is
            // deliberately uncapped so the confirmation's gate can offer
            // Buy Maximum instead of silently shrinking the entry.
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

        // Deliberately uncapped: when the fee doesn't fit, the gross must
        // exceed the balance so the confirmation's gate can offer Buy Maximum
        // explicitly instead of silently clamping.
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
