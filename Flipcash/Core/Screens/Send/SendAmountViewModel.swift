//
//  SendAmountViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

private let logger = Logger(label: "flipcash.send-amount")

@Observable
final class SendAmountViewModel {

    enum State: Equatable {
        case ready
        case submitting
        case succeeded(amount: ExchangedFiat)
    }

    var enteredAmount: String = ""
    var actionState: ButtonState = .normal
    var state: State = .ready

    var depositMint: PublicKey?

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let recipient: PublicKey
    @ObservationIgnored let recipientDisplayName: String?

    private(set) var selectedBalance: ExchangedBalance?

    var canSend: Bool {
        guard let enteredFiat else { return false }
        return enteredFiat.onChainAmount.quarks > 0
    }

    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty,
              let amount = Decimal(string: enteredAmount), amount > 0,
              let selectedBalance else { return nil }

        let mint = selectedBalance.stored.mint
        let rate = ratesController.rateForBalanceCurrency()
        let entered = FiatAmount(value: amount, currency: rate.currency)

        if mint == .usdf {
            return ExchangedFiat(nativeAmount: entered, rate: rate)
        }

        guard let supplyQuarks = selectedBalance.stored.supplyFromBonding else { return nil }

        if let viaCurve = ExchangedFiat.compute(
            fromEntered: entered,
            rate: rate,
            mint: mint,
            supplyQuarks: supplyQuarks
        ) {
            return viaCurve
        }

        // Curve cannot price requested > TVL — surface as over-balance.
        return ExchangedFiat(
            onChainAmount: TokenAmount(
                quarks: selectedBalance.stored.quarks + 1,
                mint: mint
            ),
            nativeAmount: entered,
            currencyRate: rate
        )
    }

    // MARK: - Init -

    init(
        sessionContainer: SessionContainer,
        recipient: PublicKey,
        recipientDisplayName: String?,
        mint: PublicKey? = nil,
        sender: (any DirectSending)? = nil
    ) {
        let session          = sessionContainer.session
        let ratesController  = sessionContainer.ratesController
        let resolved         = Self.resolveInitialBalance(
            mint: mint,
            session: session,
            ratesController: ratesController
        )

        self.session              = session
        self.ratesController      = ratesController
        self.sender               = sender ?? session
        self.recipient            = recipient
        self.recipientDisplayName = recipientDisplayName
        self.selectedBalance      = resolved

        if let resolved, ratesController.selectedTokenMint != resolved.stored.mint {
            ratesController.selectToken(resolved.stored.mint)
        }
    }

    private static func resolveInitialBalance(
        mint: PublicKey?,
        session: Session,
        ratesController: RatesController
    ) -> ExchangedBalance? {
        let rate = ratesController.rateForBalanceCurrency()

        if let mint, let stored = session.balance(for: mint) {
            return ExchangedBalance(stored: stored, exchangedFiat: stored.computeExchangedValue(with: rate))
        }

        let balances = session.balances(for: rate)

        if let stored = ratesController.selectedTokenMint,
           let match = balances.first(where: { $0.stored.mint == stored }) {
            return match
        }

        return balances.first
    }

    // MARK: - Action -

    func sendAction() async {
        guard case .ready = state else { return }
        guard let exchangedFiat = enteredFiat else { return }

        let result = session.hasSufficientFunds(for: exchangedFiat)
        switch result {
        case .sufficient:
            state = .submitting
            actionState = .loading

            guard let (amountToSend, pinnedState) = await prepareSubmission() else {
                state = .ready
                actionState = .normal
                session.dialogItem = .error(
                    title: "Rate Unavailable",
                    subtitle: "Couldn't get a fresh rate. Please try again."
                )
                return
            }

            let sendLimit = session.sendLimitFor(currency: amountToSend.nativeAmount.currency) ?? .zero
            guard amountToSend.nativeAmount.value <= sendLimit.nextTransaction.value else {
                logger.info("Send rejected: amount exceeds limit", metadata: [
                    "amount": "\(amountToSend.nativeAmount.formatted())",
                    "next_tx": "\(sendLimit.nextTransaction.value)",
                    "currency": "\(amountToSend.nativeAmount.currency)",
                ])
                state = .ready
                actionState = .normal
                showLimitsError()
                return
            }

            do {
                try await sender.send(
                    amount: amountToSend,
                    verifiedState: pinnedState,
                    to: recipient
                )
                Analytics.track(event: Analytics.SendEvent.sendSuccess)
                state = .succeeded(amount: amountToSend)
            } catch {
                Analytics.track(event: Analytics.SendEvent.sendFailure)
                state = .ready
                actionState = .normal
                showSendError()
            }

        case .insufficient(let shortfall):
            if let shortfall {
                showYoureShortError(amount: shortfall)
            } else {
                showInsufficientBalanceError()
            }
        }
    }

    /// Returns nil when no fresh pin is cached; otherwise the amount + pin
    /// computed against that same pin so quarks can't drift from the proof.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let selectedBalance else { return nil }
        let mint = selectedBalance.stored.mint

        guard let pin = await ratesController.currentPinnedState(
            for: ratesController.balanceCurrency,
            mint: mint
        ) else { return nil }

        guard !enteredAmount.isEmpty,
              let entered = Decimal(string: enteredAmount),
              entered > 0 else { return nil }

        let nativeEntered = FiatAmount(value: entered, currency: pin.rate.currency)

        if mint == .usdf {
            return (ExchangedFiat(nativeAmount: nativeEntered, rate: pin.rate), pin)
        }

        let balance = session.balance(for: mint)
        guard let pinnedSupply = pin.supplyFromBonding,
              let amount = ExchangedFiat.compute(
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
            Analytics.tokenInfoOpened(from: .openedFromSend, mint: depositMint)
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

    private func showSendError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't complete the transfer. Please try again."
        )
    }
}
