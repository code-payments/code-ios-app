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
    @Published var navigationPath: [GivePath] = []
    
    @Published var dialogItem: DialogItem?
    
    var canGive: Bool {
        enteredFiat != nil && (enteredFiat?.usdc.quarks ?? 0) > 0
    }
    
    let container: Container
    let sessionContainer: SessionContainer
    let session: Session
    let ratesController: RatesController
    let onrampViewModel: OnrampViewModel
    
    private(set) var selectedBalance: ExchangedBalance?
    
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
        if mint != .usdc {
            guard let supplyFromBonding = selectedBalance.stored.supplyFromBonding else {
                return nil
            }
            
            return ExchangedFiat.computeFromEntered(
                amount: amount,
                rate: ratesController.rateForEntryCurrency(),
                mint: mint,
                supplyFromBonding: supplyFromBonding
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
    
    private let isPresented: Binding<Bool>
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self.isPresented      = isPresented
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.ratesController  = sessionContainer.ratesController
        self.onrampViewModel  = sessionContainer.onrampViewModel
    }
    
    // MARK: - Action -
    
    func giveAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        let (hasSufficientFunds, delta) = session.hasSufficientFunds(for: exchangedFiat)
        
        guard hasSufficientFunds else {
            if let delta {
                showYoureShortError(amount: delta)
            } else {
                showInsufficientBalanceError()
            }
            return
        }
        
        guard session.hasLimitToSendFunds(for: exchangedFiat) else {
            showLimitsError()
            return
        }
        
        isPresented.wrappedValue = false
        
        Task {
            try await Task.delay(milliseconds: 50)
            
            session.showCashBill(
                .init(
                    kind: .cash,
                    exchangedFiat: exchangedFiat,
                    received: false
                )
            )
        }
    }
    
    func selectCurrencyAction(exchangedBalance: ExchangedBalance) {
        selectedBalance = exchangedBalance
        enteredAmount = ""
        navigationPath.append(.giveScreen)
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

enum GivePath: Hashable {
    case giveScreen
}
