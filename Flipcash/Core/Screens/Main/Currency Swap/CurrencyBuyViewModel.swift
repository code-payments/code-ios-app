//
//  CurrencyBuyViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-18.
//

import SwiftUI
import FlipcashCore
import FlipcashUI
import Logging

private let logger = Logger(label: "flipcash.swap-service")

@MainActor @Observable
class CurrencyBuyViewModel: Identifiable {
    var actionButtonState: ButtonState = .normal
    var enteredAmount: String = ""
    var dialogItem: DialogItem?
    var path: [CurrencyBuyPath] = []

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForEntryCurrency())
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else {
            return false
        }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    var screenTitle: String {
        return "Amount To Buy"
    }

    var maxPossibleAmount: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: entryRate,
            supplyQuarks: nil
        )

        guard let balance = session.balance(for: .usdf) else {
            return zero
        }

        return balance.computeExchangedValue(with: entryRate)
    }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let destination: PublicKey
    @ObservationIgnored private let currencyName: String

    // MARK: - Init -

    init(currencyPublicKey: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self.destination = currencyPublicKey
        self.currencyName = currencyName
        self.session = session
        self.ratesController = ratesController
    }

    // MARK: - Actions -

    func amountEnteredAction() {
        guard enteredFiat != nil else {
            return
        }

        performBuy()
    }

    /// Resolves the pinned state and computes the `ExchangedFiat` that will be
    /// submitted. One fetch, one rate — the quarks and the `VerifiedState`
    /// carried into `Session.buy` come from the same local so the submitted
    /// quarks can't drift from the rate the server validates against.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        let currency = ratesController.entryCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: .usdf) else {
            return nil
        }
        guard let amount = computeAmount(using: pin.rate) else {
            return nil
        }
        return (amount, pin)
    }

    /// Shared compute used by the display preview (live rate) and the submit
    /// path (pinned rate). Same quark math, different rate source.
    private func computeAmount(using rate: Rate) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        let mint: PublicKey = .usdf
        let entered = ExchangedFiat(
            nativeAmount: FiatAmount(value: amount, currency: rate.currency),
            rate: rate
        )

        // Cap to balance to handle rounding differences between display and entry. Since our display rounds HALF_UP
        guard let balance = session.balance(for: .usdf) else {
            return entered
        }

        // If entered USDF value exceeds balance, cap it to the balance
        if entered.usdfValue.value > balance.usdf.value {
            return ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: balance.quarks, mint: mint),
                rate: rate,
                supplyQuarks: nil
            )
        }

        return entered
    }

    private func performBuy() {
        actionButtonState = .loading

        Task {
            guard let (buyAmount, pin) = await prepareSubmission() else {
                actionButtonState = .normal
                dialogItem = .staleRate
                return
            }

            let sendLimit = session.sendLimitFor(currency: buyAmount.nativeAmount.currency) ?? .zero

            guard buyAmount.nativeAmount.value <= sendLimit.maxPerDay.value else {
                logger.info("Buy rejected: amount exceeds limit", metadata: [
                    "amount": "\(buyAmount.nativeAmount.formatted())",
                    "max_per_day": "\(sendLimit.maxPerDay.value)",
                    "currency": "\(buyAmount.nativeAmount.currency)",
                ])
                actionButtonState = .normal
                showLimitsError()
                return
            }

            do {
                let swapId = try await session.buy(amount: buyAmount, verifiedState: pin, of: destination)
                path.append(.processing(swapId: swapId, currencyName: currencyName, amount: buyAmount))
            } catch Session.Error.insufficientBalance {
                actionButtonState = .normal
                showInsufficientBalanceError()
            } catch Session.Error.verifiedStateStale {
                // Session.assertFresh already logged this at .warning. The catch
                // exists only to reset the button so the user can retry.
                actionButtonState = .normal
            } catch {
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to buy currency",
                    metadata: [
                        "mint": destination.base58,
                        "amount": buyAmount.nativeAmount.formatted(),
                    ]
                )
                actionButtonState = .normal
                showGenericError()
            }
        }
    }

    // MARK: - Reset -

    private func resetEnteredAmount() {
        enteredAmount = ""
    }

    // MARK: - Dialogs -

    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "Insufficient Balance",
            subtitle: "Please enter a lower amount and try again",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    private func showLimitsError() {
        dialogItem = .init(
            style: .destructive,
            title: "Transaction Limit Reached",
            subtitle: "You can only buy up to the transaction limit at a time",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    private func showGenericError() {
        dialogItem = .init(
            style: .destructive,
            title: "Something Went Wrong",
            subtitle: "Please try again later",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

enum CurrencyBuyPath: Hashable {
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}
