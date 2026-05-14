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
final class BuyAmountViewModel: Identifiable {
    var actionButtonState: ButtonState = .normal
    var enteredAmount: String = ""
    var dialogItem: DialogItem?
    var pendingOperation: PaymentOperation?

    @ObservationIgnored let mint: PublicKey
    @ObservationIgnored let currencyName: String

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForBalanceCurrency())
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else { return false }
        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    /// Single-transaction cap exposed by the server via `Limits.sendLimitFor`.
    /// Matches what `EnterAmountView`'s subtitle renders for `.buy` mode, so
    /// the in-view cap and the view-model gate stay aligned.
    ///
    /// This is the daily send limit, not a balance-derived cap: the buy flow
    /// must allow amounts that exceed the user's current USDF balance, since
    /// funding (Apple Pay / Phantom / etc.) tops it up.
    var maxPossibleAmount: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let maxNative = session.sendLimitFor(currency: rate.currency)?.maxPerDay
            ?? FiatAmount.zero(in: rate.currency)
        return ExchangedFiat(nativeAmount: maxNative, rate: rate)
    }

    var screenTitle: String { "Amount" }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self.mint = mint
        self.currencyName = currencyName
        self.session = session
        self.ratesController = ratesController
    }

    // MARK: - Submission

    /// Single source of truth for amount submission. Pin verified state, compute
    /// quarks against the pin, run limit + balance gates, then either submit
    /// the buy directly (when USDF covers the amount) or hand off to the
    /// funding picker via ``pendingMethodSelection``.
    func amountEnteredAction(router: AppRouter) async {
        guard enteredFiat != nil else { return }
        actionButtonState = .loading

        guard let (amount, pin) = await prepareSubmission() else {
            actionButtonState = .normal
            dialogItem = .staleRate
            return
        }

        let sendLimit = session.sendLimitFor(currency: amount.nativeAmount.currency) ?? .zero
        guard amount.nativeAmount.value <= sendLimit.maxPerDay.value else {
            logger.info("Buy rejected: amount exceeds limit", metadata: [
                "amount": "\(amount.nativeAmount.formatted())",
                "max_per_day": "\(sendLimit.maxPerDay.value)",
                "currency": "\(amount.nativeAmount.currency)",
            ])
            actionButtonState = .normal
            showLimitsError()
            return
        }

        if usdfBalanceCovers(amount) {
            await performBuy(amount: amount, pin: pin, router: router)
        } else {
            actionButtonState = .normal
            routeToPicker(amount: amount, pin: pin)
        }
    }

    private func routeToPicker(amount: ExchangedFiat, pin: VerifiedState) {
        pendingOperation = .buy(.init(
            mint: mint,
            currencyName: currencyName,
            amount: amount,
            verifiedState: pin
        ))
    }

    private func usdfBalanceCovers(_ amount: ExchangedFiat) -> Bool {
        guard let balance = session.balance(for: .usdf) else { return false }
        return balance.usdf.value >= amount.usdfValue.value
    }

    private func performBuy(amount: ExchangedFiat, pin: VerifiedState, router: AppRouter) async {
        do {
            Analytics.buttonTapped(name: .buyWithReserves)
            let swapId = try await session.buy(amount: amount, verifiedState: pin, of: mint)
            actionButtonState = .normal
            router.pushAny(BuyFlowPath.processing(
                swapId: swapId,
                currencyName: currencyName,
                amount: amount,
                swapType: .buyWithReserves
            ))
        } catch Session.Error.insufficientBalance {
            // Race: balance gate said OK but session.buy disagreed. Route to picker.
            actionButtonState = .normal
            routeToPicker(amount: amount, pin: pin)
        } catch Session.Error.verifiedStateStale {
            actionButtonState = .normal
        } catch {
            logger.error("Failed to buy currency from BuyAmountScreen", metadata: [
                "mint": "\(mint.base58)",
                "amount": "\(amount.nativeAmount.formatted())",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(
                error,
                reason: "Failed to buy currency from BuyAmountScreen",
                metadata: ["mint": mint.base58, "amount": amount.nativeAmount.formatted()]
            )
            actionButtonState = .normal
            dialogItem = .somethingWentWrong
        }
    }

    /// Pin verified state once, compute amount against the pin so quarks
    /// stay tied to the rate the server is about to verify.
    private func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        let currency = ratesController.balanceCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: .usdf) else {
            return nil
        }
        guard let amount = computeAmount(using: pin.rate) else { return nil }
        return (amount, pin)
    }

    private func computeAmount(using rate: Rate) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        // Use Decimal(string:) — the keypad always emits "." regardless of locale.
        // NumberFormatter.decimal(from:) breaks on non-"." locales (CLAUDE.md pitfall).
        guard let amount = Decimal(string: enteredAmount) else { return nil }
        return ExchangedFiat(
            nativeAmount: FiatAmount(value: amount, currency: rate.currency),
            rate: rate
        )
    }

    // MARK: - Dialogs

    private func showLimitsError() {
        dialogItem = .init(
            style: .destructive,
            title: "Transaction Limit Reached",
            subtitle: "You can only buy up to the transaction limit at a time",
            dismissable: true
        ) { .okay(kind: .destructive) }
    }
}
