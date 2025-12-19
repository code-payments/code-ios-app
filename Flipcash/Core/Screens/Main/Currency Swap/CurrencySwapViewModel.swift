//
//  CurrencySwapViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-18.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
class CurrencySwapViewModel: ObservableObject {
    @Published var actionButtonState: ButtonState = .normal
    @Published var enteredAmount: String = ""
    @Published var dialogItem: DialogItem?
        
    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
                
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }
        
        let mint: PublicKey = .usdc
        
        let rate = ratesController.rateForEntryCurrency()
        
        return try! ExchangedFiat(
            underlying: .init(
                fiatDecimal: amount,
                currencyCode: rate.currency,
                decimals: mint.mintDecimals
            ),
            rate: rate,
            mint: mint
        )
    }
        
    var canPerformAction: Bool {
        return enteredFiat != nil
    }
    
    var screenTitle: String {
        return "Amount To Buy"
    }
    
    var maxPossibleAmount: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero      = try! ExchangedFiat(underlying: 0, rate: entryRate, mint: .usdc)
        
        guard let balance = session.balance(for: .usdc) else {
            return zero
        }
        
        return balance.computeExchangedValue(with: entryRate)
    }
    
    private let container: Container
    private let client: Client
    private let session: Session
    private let ratesController: RatesController
    private let destination: PublicKey
    
    // MARK: - Init -
    
    init(currencyPublicKey: PublicKey, container: Container, sessionContainer: SessionContainer) {
        self.destination     = currencyPublicKey
        self.container       = container
        self.client          = container.client
        self.session         = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
    }
        
    // MARK: - Actions -
    
    func reset() {
        actionButtonState = .normal
        enteredAmount = ""
    }
    
    func amountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        let result = session.hasSufficientFunds(for: exchangedFiat)

        // Use switch for exhaustive checking - compiler will error if new cases are added
        switch result {
        case .sufficient(_):
            performBuy()

        case .insufficient:
            showInsufficientBalanceError()
        }
    }
        
    private func performBuy() {
        guard let buyAmount = enteredFiat else {
            return
        }
        
        actionButtonState = .loading
        
        Task {
            try? await session.buy(amount: buyAmount, of: destination)
        }
        
        showSuccessDialog()
    }
        
    // MARK: - Reset -
    
    private func resetEnteredAmount() {
        enteredAmount = ""
    }
        
    // MARK: - Dialogs -
    
    private func showSuccessDialog() {
        dialogItem = .init(
            style: .success,
            title: "Your Funds Will Be Available Soon",
            subtitle: "They should be available in a few minutes. If you have any issues please contact support@flipcash.com",
            dismissable: false
        ) {
            .okay(kind: .standard) { [weak self] in
                self?.actionButtonState = .success
            }
        }
    }
    
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
