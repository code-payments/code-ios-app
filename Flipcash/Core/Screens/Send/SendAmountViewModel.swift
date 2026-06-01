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

    /// Result of a send attempt. `.success` and `.recipientNotFound` both return
    /// the screen to the contact list; `.failed` keeps it on amount entry. Error
    /// copy is surfaced internally via `session.dialogItem`.
    enum SendOutcome: Equatable {
        case success
        case recipientNotFound
        case failed
    }

    var enteredAmount: String = ""

    var depositMint: PublicKey?

    @ObservationIgnored let session: Session
    @ObservationIgnored let ratesController: RatesController
    @ObservationIgnored let sender: any DirectSending
    @ObservationIgnored let resolver: any RecipientResolving
    @ObservationIgnored let contact: ResolvedContact

    private(set) var selectedBalance: ExchangedBalance?

    /// Cached after the first successful resolve so a retried send (e.g. after a
    /// transient send failure) skips the round-trip.
    private var resolvedRecipient: PublicKey?

    /// Amount validity only — never gated on the recipient. A red subtitle in
    /// `EnterAmountView` (driven by `!canSend`) therefore means over-limit, not
    /// "recipient unresolved"; resolution happens on the Send tap instead.
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
        contact: ResolvedContact,
        mint: PublicKey? = nil,
        sender: (any DirectSending)? = nil,
        resolver: (any RecipientResolving)? = nil
    ) {
        let session          = sessionContainer.session
        let ratesController  = sessionContainer.ratesController
        let resolved         = Self.resolveInitialBalance(
            mint: mint,
            session: session,
            ratesController: ratesController
        )

        self.session         = session
        self.ratesController = ratesController
        self.sender          = sender ?? session
        self.resolver        = resolver ?? session
        self.contact         = contact
        self.selectedBalance = resolved

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

    /// Validates the amount locally, resolves the recipient on the Send tap
    /// (retrying a transient network failure), then submits. The control owns
    /// the loading/checkmark state; this returns only where to go next.
    @discardableResult
    func sendAction() async -> SendOutcome {
        guard let exchangedFiat = enteredFiat else { return .failed }

        switch session.hasSufficientFunds(for: exchangedFiat) {
        case .insufficient(let shortfall):
            if let shortfall {
                showYoureShortError(amount: shortfall)
            } else {
                showInsufficientBalanceError()
            }
            return .failed

        case .sufficient:
            let recipient: PublicKey
            switch await resolveRecipient() {
            case .resolved(let owner):
                recipient = owner
            case .notFound:
                showRecipientNotFoundError()
                return .recipientNotFound
            case .failed:
                showResolveFailedError()
                return .failed
            }

            guard let (amountToSend, pinnedState) = await prepareSubmission() else {
                session.dialogItem = .error(
                    title: "Rate Unavailable",
                    subtitle: "Couldn't get a fresh rate. Please try again."
                )
                return .failed
            }

            let sendLimit = session.sendLimitFor(currency: amountToSend.nativeAmount.currency) ?? .zero
            guard amountToSend.nativeAmount.value <= sendLimit.nextTransaction.value else {
                logger.info("Send rejected: amount exceeds limit", metadata: [
                    "amount": "\(amountToSend.nativeAmount.formatted())",
                    "next_tx": "\(sendLimit.nextTransaction.value)",
                    "currency": "\(amountToSend.nativeAmount.currency)",
                ])
                showLimitsError()
                return .failed
            }

            do {
                try await sender.send(
                    amount: amountToSend,
                    verifiedState: pinnedState,
                    to: recipient
                )
                Analytics.track(event: Analytics.SendEvent.sendSuccess)
                return .success
            } catch {
                Analytics.track(event: Analytics.SendEvent.sendFailure)
                showSendError()
                return .failed
            }
        }
    }

    // MARK: - Recipient resolution -

    private enum RecipientResolution {
        case resolved(PublicKey)
        case notFound
        case failed(Error)
    }

    /// Resolves the recipient, retrying once on a transient network error, and
    /// records resolve telemetry. A successful resolution is cached so a
    /// retried send skips the round-trip (and isn't re-counted).
    private func resolveRecipient() async -> RecipientResolution {
        if let resolvedRecipient {
            return .resolved(resolvedRecipient)
        }
        for attempt in 0..<2 {
            do {
                let owner = try await resolver.resolveContact(e164: contact.phoneE164)
                Analytics.track(event: Analytics.SendEvent.resolveSuccess)
                resolvedRecipient = owner
                return .resolved(owner)
            } catch ErrorResolve.notFound {
                Analytics.track(event: Analytics.SendEvent.resolveNotFound)
                logger.info("Recipient not on Flipcash", metadata: ["contactId": "\(contact.contactId)"])
                return .notFound
            } catch ErrorResolve.networkError where attempt == 0 {
                continue
            } catch {
                Analytics.track(event: Analytics.SendEvent.resolveError)
                logger.error("Recipient resolve failed", metadata: ["contactId": "\(contact.contactId)", "error": "\(error)"])
                ErrorReporting.captureError(error, reason: "Contact resolve failed")
                return .failed(error)
            }
        }
        return .failed(ErrorResolve.networkError)
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

    private func showRecipientNotFoundError() {
        session.dialogItem = .error(
            title: "Not on Flipcash",
            subtitle: "This contact isn't on Flipcash. Pick someone else to send cash."
        )
    }

    private func showResolveFailedError() {
        session.dialogItem = .error(
            title: "Couldn't Send",
            subtitle: "We couldn't reach the network. Please try again."
        )
    }
}
