//
//  GiveViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class GiveViewModel: ObservableObject {
    
    @Published var enteredAmount: String = ""
    @Published var actionState: ButtonState = .normal
    
    @Published var dialogItem: DialogItem?
    
    var canGive: Bool {
        enteredFiat != nil && (enteredFiat?.underlying.quarks ?? 0) > 0
    }
    
    let container: Container
    let sessionContainer: SessionContainer
    let session: Session
    let ratesController: RatesController
    let onrampViewModel: OnrampViewModel
    
    @Published private(set) var selectedBalance: ExchangedBalance?
    
    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount), amount > 0 else {
            return nil
        }
        
        guard let selectedBalance else {
            return nil
        }
        
        let mint = selectedBalance.stored.mint
        
        // Only applies for bonded tokens
        if mint != .usdf {
            guard let supplyQuarks = selectedBalance.stored.supplyFromBonding else {
                return nil
            }

            let rate = ratesController.rateForEntryCurrency()
            return ExchangedFiat.computeFromEntered(
                amount: amount,
                rate: rate,
                mint: mint,
                supplyQuarks: supplyQuarks
            )
            
        } else {
            let rate = ratesController.rateForEntryCurrency()
            return try! ExchangedFiat(
                converted: .init(
                    fiatDecimal: amount,
                    currencyCode: rate.currency,
                    decimals: mint.mintDecimals
                ),
                rate: rate,
                mint: mint
            )
        }
    }
    
    @Published var isPresented = false {
        didSet {
            if isPresented {
                self.enteredAmount = ""
            }
            
        }
    }
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.isPresented      = false
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.ratesController  = sessionContainer.ratesController
        self.onrampViewModel  = sessionContainer.onrampViewModel
        
        // Session now guarantees a valid token is selected if balances exist
        let rate = ratesController.rateForEntryCurrency()
        if let selectedTokenMint = ratesController.selectedTokenMint {
            self.selectedBalance = sessionContainer.session.balances(for: rate)
                .first(where: { $0.stored.mint == selectedTokenMint })
        } else {
            // Fallback to highest balance if somehow no token is selected
            self.selectedBalance = sessionContainer.session.balances(for: rate).first
        }
    }
    
    // MARK: - Action -
    
    func giveAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        let result = session.hasSufficientFunds(for: exchangedFiat)
        switch result {
        case .sufficient(let amountToSend):
            guard session.hasLimitToSendFunds(for: amountToSend) else {
                showLimitsError()
                return
            }

            isPresented = false

            Task {
                try await Task.delay(milliseconds: 50)

                session.showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: amountToSend,
                        received: false
                    )
                )
            }

        case .insufficient(let shortfall):
            if let shortfall {
                showYoureShortError(amount: shortfall)
            } else {
                showInsufficientBalanceError()
            }
        }
    }
    
    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        ratesController.selectToken(exchangedBalance.stored.mint)
        enteredAmount = ""
    }
    
    // MARK: - Navigation -
    
    private func presentOnramp() {
        onrampViewModel.presentRoot()
        Analytics.onrampOpenedFromGive()
    }
    
    // MARK: - Errors -
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showYoureShortError(amount: ExchangedFiat) {
        dialogItem = .init(
            style: .destructive,
            title: "You're \(amount.converted.formatted()) Short",
            subtitle: "Add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showLimitsError() {
        dialogItem = .init(
            style: .destructive,
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}
