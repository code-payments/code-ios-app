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

@Observable
final class GiveViewModel {

    var enteredAmount: String = ""
    var actionState: ButtonState = .normal

    var depositMint: PublicKey?

    var canGive: Bool {
        enteredFiat != nil && (enteredFiat?.onChainAmount.quarks ?? 0) > 0
    }

    @ObservationIgnored let container: Container
    @ObservationIgnored let sessionContainer: SessionContainer
    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored private let amountValidator = AmountValidator()

    private(set) var selectedBalance: ExchangedBalance?

    private var enteredFiat: ExchangedFiat? {
        guard let amount = amountValidator.validate(enteredAmount),
              let selectedBalance else { return nil }
        return selectedBalance.enteredFiat(
            for: amount,
            rate: ratesController.rateForBalanceCurrency()
        )
    }

    // MARK: - Init -

    /// The `selectToken` sync is the only visible side-effect; the `if mismatch`
    /// guard makes it idempotent across repeated inits.
    init(container: Container, sessionContainer: SessionContainer, mint: PublicKey?) {
        let session          = sessionContainer.session
        let ratesController  = sessionContainer.ratesController
        let resolved         = ratesController.resolveInitialBalance(mint: mint, session: session)

        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = session
        self.ratesController  = ratesController
        self.selectedBalance  = resolved

        if let resolved, ratesController.selectedTokenMint != resolved.stored.mint {
            ratesController.selectToken(resolved.stored.mint)
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
                    session.dialogItem = .error(title: "Rate Unavailable", subtitle: "Couldn't get a fresh rate. Please try again.")
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

                try await Task.delay(milliseconds: 50)

                session.showCashBill(
                    .init(
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
    /// when no fresh pin is cached; caller surfaces a rate-unavailable error.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let selectedBalance else { return nil }
        let mint = selectedBalance.stored.mint

        guard let pin = await ratesController.currentPinnedState(
            for: ratesController.balanceCurrency,
            mint: mint
        ) else { return nil }

        guard !enteredAmount.isEmpty,
              let entered = amountValidator.validate(enteredAmount),
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

    private func showInsufficientBalanceError() {
        session.dialogItem = .error(
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showYoureShortError(amount: ExchangedFiat) {
        session.dialogItem = .error(
            title: "You're \(amount.nativeAmount.formatted()) Short",
            subtitle: "Add more cash, or try again with a lower amount"
        ) {
            .destructive("Add More Cash") { [weak self] in
                self?.presentDeposit()
            };
            .dismiss(kind: .subtle)
        }
    }

    private func showLimitsError() {
        session.dialogItem = .error(
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily"
        )
    }
}
