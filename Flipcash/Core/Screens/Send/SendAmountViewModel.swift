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

    /// Drives the screen between amount entry and the success view.
    /// `.submitting` blocks duplicate submissions while the transfer is in
    /// flight; `.succeeded` swaps the screen body to the auto-dismissing
    /// confirmation.
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

    /// Drives `EnterAmountView`'s `actionEnabled` closure. Must reflect only
    /// the entered amount's validity — `EnterAmountView` reuses this signal
    /// to colour the subtitle red when the entered value is past the limit,
    /// so gating on `state` here would paint the subtitle red the instant
    /// `sendAction()` transitions to `.submitting`. State-based re-entry
    /// is guarded inside `sendAction()` itself; the button's loading visual
    /// comes from `actionState`.
    var canSend: Bool {
        guard let enteredFiat else { return false }
        return enteredFiat.onChainAmount.quarks > 0
    }

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

            let rate = ratesController.rateForBalanceCurrency()
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
            // over-balance request and returns `.insufficient`.
            return ExchangedFiat(
                onChainAmount: TokenAmount(
                    quarks: selectedBalance.stored.quarks + 1,
                    mint: mint
                ),
                nativeAmount: entered,
                currencyRate: rate
            )

        } else {
            let rate = ratesController.rateForBalanceCurrency()
            return ExchangedFiat(
                nativeAmount: FiatAmount(value: amount, currency: rate.currency),
                rate: rate
            )
        }
    }

    // MARK: - Init -

    /// `sender` defaults to the session, which conforms to `DirectSending`.
    /// Tests inject `MockSession` to record the call without dialing the
    /// network — same handler-injection pattern as `ReservesFundingOperation`.
    init(
        sessionContainer: SessionContainer,
        recipient: PublicKey,
        recipientDisplayName: String?,
        mint: PublicKey?,
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

    /// Same two-tier fallback as `GiveViewModel`: caller's `mint` wins,
    /// otherwise the previously-selected token, otherwise the first non-USDF
    /// balance — falling back to whatever first balance exists (USDF if no
    /// other token has positive balance).
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
                logger.error("Send failed", metadata: ["error": "\(error)"])
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

    /// Resolves the pin and computes the bill amount against it — one fetch
    /// for both, so quarks can't drift from the submitted pin. Returns nil
    /// when no fresh pin is cached.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let selectedBalance else { return nil }
        let mint = selectedBalance.stored.mint

        guard let pin = await ratesController.currentPinnedState(
            for: ratesController.balanceCurrency,
            mint: mint
        ) else { return nil }

        guard !enteredAmount.isEmpty,
              let entered = NumberFormatter.decimal(from: enteredAmount),
              entered > 0 else { return nil }

        let nativeEntered = FiatAmount(value: entered, currency: pin.rate.currency)
        let balance = session.balance(for: mint)

        if mint == .usdf {
            let amount = ExchangedFiat(
                nativeAmount: nativeEntered,
                rate: pin.rate
            )
            return (amount, pin)
        }

        guard let pinnedSupply = pin.supplyFromBonding else { return nil }
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
