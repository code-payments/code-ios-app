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
        enteredFiat != nil && (enteredFiat?.onChainAmount.quarks ?? 0) > 0
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
            let entered = FiatAmount(value: amount, currency: rate.currency)

            if let viaCurve = ExchangedFiat.compute(
                fromEntered: entered,
                rate: rate,
                mint: mint,
                supplyQuarks: supplyQuarks
            ) {
                return viaCurve
            }

            // Curve could not price the entered amount (requested > TVL).
            // Build a synthetic ExchangedFiat so `hasSufficientFunds` sees an
            // over-balance request and returns `.insufficient` with a shortfall
            // derived from `nativeAmount`. The onChainAmount is a sentinel —
            // this ExchangedFiat is never transported.
            return ExchangedFiat(
                onChainAmount: TokenAmount(
                    quarks: selectedBalance.stored.quarks + 1,
                    mint: mint
                ),
                nativeAmount: entered,
                currencyRate: rate
            )

        } else {
            let rate = ratesController.rateForEntryCurrency()
            return ExchangedFiat(
                nativeAmount: FiatAmount(value: amount, currency: rate.currency),
                rate: rate
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
        case .sufficient:
            Task {
                guard let (amountToSend, pinnedState) = await prepareSubmission() else {
                    dialogItem = .staleRate
                    return
                }

                let sendLimit = session.sendLimitFor(currency: amountToSend.nativeAmount.currency) ?? .zero

                guard amountToSend.nativeAmount.value <= sendLimit.nextTransaction.value else {
                    logger.info("Give rejected: amount exceeds limit", metadata: [
                        "amount": "\(amountToSend.nativeAmount.formatted())",
                        "next_tx": "\(sendLimit.nextTransaction.value)",
                        "currency": "\(amountToSend.nativeAmount.currency)",
                    ])
                    showLimitsError()
                    return
                }

                isPresented = false

                try await Task.delay(milliseconds: 50)

                session.showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: amountToSend,
                        received: false,
                        verifiedState: pinnedState
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

    /// Resolves the pin and computes the bill amount against it — one fetch
    /// for both, so quarks can't drift from the submitted pin. Returns nil
    /// when no fresh pin is cached; caller surfaces `.staleRate`.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let selectedBalance else { return nil }
        let mint = selectedBalance.stored.mint

        guard let pin = await ratesController.currentPinnedState(
            for: ratesController.entryCurrency,
            mint: mint
        ) else { return nil }

        guard !enteredAmount.isEmpty,
              let entered = NumberFormatter.decimal(from: enteredAmount),
              entered > 0 else { return nil }

        guard let pinnedSupply = pin.supplyFromBonding else { return nil }

        let nativeEntered = FiatAmount(value: entered, currency: pin.rate.currency)
        let balance = session.balance(for: mint)

        guard let amount = ExchangedFiat.compute(
            fromEntered: nativeEntered,
            rate: pin.rate,
            mint: mint,
            supplyQuarks: pinnedSupply,
            balance: balance.map(\.usdf),
            tokenBalanceQuarks: balance?.quarks
        ) else { return nil }

        return (amount, pin)
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
            title: "You're \(amount.nativeAmount.formatted()) Short",
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
