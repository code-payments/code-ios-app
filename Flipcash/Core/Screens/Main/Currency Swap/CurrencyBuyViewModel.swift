//
//  CurrencyBuyViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-18.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
class CurrencyBuyViewModel: ObservableObject {
    @Published var actionButtonState: ButtonState = .normal
    @Published var enteredAmount: String = ""
    @Published var dialogItem: DialogItem?
    @Published var path: [CurrencyBuyPath] = []
        
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
        return enteredFiat != nil
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
    
    private let session: Session
    private let ratesController: RatesController
    private let destination: PublicKey

    // MARK: - Init -

    init(currencyPublicKey: PublicKey, container: Container, sessionContainer: SessionContainer) {
        self.destination     = currencyPublicKey
        self.session         = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
    }
        
    // MARK: - Actions -
    
    func reset() {
        actionButtonState = .normal
        enteredAmount = ""
        path = []
    }
    
    func amountEnteredAction() {
        guard enteredFiat != nil else {
            return
        }

        performBuy()
    }
            
    private func performBuy() {
        guard let buyAmount = enteredFiat else { return }

        actionButtonState = .loading

        Task {
            do {
                let swapId = try await session.buy(amount: buyAmount, of: destination)

                await MainActor.run {
                    path.append(.processing(swapId: swapId))
                }
            } catch {
                await MainActor.run {
                    actionButtonState = .normal
                    showInsufficientBalanceError()
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
}

enum CurrencyBuyPath: Hashable {
    case processing(swapId: SwapId)
}
