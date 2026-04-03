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
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        let mint: PublicKey = .usdf
        let rate = ratesController.rateForEntryCurrency()

        let entered = try! ExchangedFiat(
            converted: .init(
                fiatDecimal: amount,
                currencyCode: rate.currency,
                decimals: mint.mintDecimals
            ),
            rate: rate,
            mint: mint
        )

        // Cap to balance to handle rounding differences between display and entry. Since our display rounds HALF_UP
        guard let balance = session.balance(for: .usdf) else {
            return entered
        }

        // If entered underlying exceeds balance, cap it to the balance
        if entered.underlying.quarks > balance.quarks {
            return try? ExchangedFiat(
                underlying: Quarks(
                    quarks: balance.quarks,
                    currencyCode: .usd,
                    decimals: mint.mintDecimals
                ),
                rate: rate,
                mint: mint
            )
        }

        return entered
    }
        
    var canPerformAction: Bool {
        guard enteredFiat != nil else {
            return false
        }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.converted
        )
    }
    
    var screenTitle: String {
        return "Amount To Buy"
    }
    
    var maxPossibleAmount: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero = try! ExchangedFiat(underlying: 0, rate: entryRate, mint: .usdf)
        
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
        self.destination     = currencyPublicKey
        self.currencyName    = currencyName
        self.session         = session
        self.ratesController = ratesController
    }
        
    // MARK: - Actions -

    func amountEnteredAction() {
        guard enteredFiat != nil else {
            return
        }

        performBuy()
    }
            
    private func performBuy() {
        guard let buyAmount = enteredFiat else { return }

        let sendLimit = session.sendLimitFor(currency: buyAmount.converted.currencyCode) ?? .zero

        guard buyAmount.converted <= sendLimit.maxPerDay else {
            logger.info("Buy rejected: amount exceeds limit", metadata: [
                "amount": "\(buyAmount.converted.formatted())",
                "max_per_day": "\(sendLimit.maxPerDay.decimalValue)",
                "currency": "\(buyAmount.converted.currencyCode)",
            ])
            showLimitsError()
            return
        }

        actionButtonState = .loading

        Task {
            do {
                let swapId = try await session.buy(amount: buyAmount, of: destination)

                await MainActor.run {
                    path.append(.processing(swapId: swapId, currencyName: currencyName, amount: buyAmount))
                }
            } catch Session.Error.insufficientBalance {
                await MainActor.run {
                    actionButtonState = .normal
                    showInsufficientBalanceError()
                }
            } catch {
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to buy currency",
                    metadata: [
                        "mint": destination.base58,
                        "amount": buyAmount.converted.formatted(),
                        "quarks": "\(buyAmount.underlying.quarks)",
                    ]
                )
                await MainActor.run {
                    actionButtonState = .normal
                    showGenericError()
                }
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
