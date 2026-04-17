//
//  GiveViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-10-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import Logging

private let logger = Logger(label: "flipcash.send-cash")

@MainActor @Observable
class GiveViewModel {

    var enteredAmount: String = ""
    var actionState: ButtonState = .normal

    var dialogItem: DialogItem?
    var depositMint: PublicKey?

    var canGive: Bool {
        enteredFiat != nil && (enteredFiat?.underlying.quarks ?? 0) > 0
    }

    @ObservationIgnored let container: Container
    @ObservationIgnored let sessionContainer: SessionContainer
    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController

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
        if mint != .usdf {
            guard let supplyQuarks = selectedBalance.stored.supplyFromBonding else {
                return nil
            }

            let rate = ratesController.rateForEntryCurrency()
            return ExchangedFiat.computeFromEntered(
                amount: amount,
                rate: rate,
                mint: mint,
                supplyQuarks: supplyQuarks,
                balance: selectedBalance.stored.usdf,
                tokenBalanceQuarks: selectedBalance.stored.quarks
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
    
    var isPresented = false {
        didSet {
            if isPresented {
                let rate = ratesController.rateForBalanceCurrency()
                let hasGiveableBalance = session.balances(for: rate).contains { $0.stored.mint != .usdf }

                if hasGiveableBalance {
                    refreshSelectedBalance()
                    self.enteredAmount = ""
                } else {
                    self.isPresented = false
                    showNoBalanceError()
                }
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
    }

    private func refreshSelectedBalance() {
        let rate = ratesController.rateForEntryCurrency()
        let availableBalances = session.balances(for: rate)
            .filter { $0.stored.mint != .usdf }

        if let selectedTokenMint = ratesController.selectedTokenMint,
           let match = availableBalances.first(where: { $0.stored.mint == selectedTokenMint }) {
            selectedBalance = match
        } else if let first = availableBalances.first {
            selectedBalance = first
            ratesController.selectToken(first.stored.mint)
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
            let sendLimit = session.sendLimitFor(currency: amountToSend.converted.currencyCode) ?? .zero

            guard amountToSend.converted <= sendLimit.nextTransaction else {
                logger.info("Give rejected: amount exceeds limit", metadata: [
                    "amount": "\(amountToSend.converted.formatted())",
                    "next_tx": "\(sendLimit.nextTransaction.decimalValue)",
                    "currency": "\(amountToSend.converted.currencyCode)",
                ])
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
    
    private func presentDeposit() {
        depositMint = selectedBalance?.stored.mint
        if let depositMint {
            Analytics.tokenInfoOpened(from: .openedFromGive, mint: depositMint)
        }
    }
    
    // MARK: - Errors -
    
    private func showNoBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "No Balance Yet",
            subtitle: "Get another Flipcash user to give you some cash to get a balance",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }

    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
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
                self?.presentDeposit()
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
