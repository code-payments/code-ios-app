//
//  AddMoneyAmountViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.add-money-amount")

@Observable
@MainActor
final class AddMoneyAmountViewModel {

    var enteredAmount: String = ""
    var dialogItem: DialogItem?
    var actionButtonState: ButtonState = .normal

    /// View model for the Coinbase verification sheet, set when the
    /// verified-contact gate runs.
    var verificationViewModel: OnrampVerification?

    let method: DepositMethod

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let amountValidator: AmountValidator

    @ObservationIgnored private var depositTask: Task<Void, Never>?

    var screenTitle: String { "Amount to Add" }

    /// The method-specific action button title.
    var actionTitle: String {
        switch method {
        case .coinbase:    "Add Money"
        case .phantom:     "Confirm in Phantom"
        case .otherWallet: "Add Money"
        }
    }

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForBalanceCurrency())
    }

    /// The cap the entry field both renders and gates against — the server's
    /// daily send limit.
    var maxPossibleAmount: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let maxNative = session.sendLimitFor(currency: rate.currency)?.maxPerDay
            ?? FiatAmount.zero(in: rate.currency)
        return ExchangedFiat(nativeAmount: maxNative, rate: rate)
    }

    var canAdd: Bool {
        guard enteredFiat != nil else { return false }
        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    init(
        method: DepositMethod,
        session: Session,
        ratesController: RatesController,
        amountValidator: AmountValidator = AmountValidator()
    ) {
        self.method = method
        self.session = session
        self.ratesController = ratesController
        self.amountValidator = amountValidator
    }

    // MARK: - Action

    /// Starts the selected deposit method's operation, calling `onProceed` on
    /// success. No verified-state pin is needed — a deposit delivers to an
    /// address rather than spending reserves.
    func addMoney(
        coinbaseService: CoinbaseService,
        verificationCoordinator: VerificationCoordinator,
        walletConnection: any TransactionSigning,
        onProceed: @escaping (AddMoneyProcessingInput) -> Void
    ) {
        guard let amount = enteredFiat else { return }

        switch method {
        case .coinbase:
            startCoinbaseDeposit(
                amount: amount,
                coinbaseService: coinbaseService,
                verificationCoordinator: verificationCoordinator,
                onProceed: onProceed
            )
        case .phantom:
            startPhantomDeposit(
                amount: amount,
                walletConnection: walletConnection,
                onProceed: onProceed
            )
        case .otherWallet:
            // Other Wallet never routes through amount entry.
            logger.warning("Add money amount screen reached with .otherWallet method")
        }
    }

    private func startCoinbaseDeposit(
        amount: ExchangedFiat,
        coinbaseService: CoinbaseService,
        verificationCoordinator: VerificationCoordinator,
        onProceed: @escaping (AddMoneyProcessingInput) -> Void
    ) {
        verificationCoordinator.runGated(
            for: session,
            bind: { [weak self] vm in self?.verificationViewModel = vm }
        ) { [weak self] in
            guard let self else { return }
            let operation = CoinbaseDepositOperation(coinbaseService: coinbaseService, session: session)
            depositTask = Task { [weak self, operation] in
                self?.actionButtonState = .loading
                defer { self?.actionButtonState = .normal }
                do {
                    try await operation.start(amount: amount)
                    onProceed(.init(amount: amount, method: .coinbase, depositRef: operation.orderId))
                } catch is CancellationError {
                    // Distinguish the 60s idle-timeout cancel from a plain
                    // user-dismiss, which stays silent.
                    if operation.didTimeOut {
                        self?.dialogItem = .info(
                            title: "Purchase Timed Out",
                            subtitle: "Purchases must be authorized within 60 seconds"
                        )
                    }
                } catch let DepositError.externalRejected(title, subtitle) {
                    self?.dialogItem = .error(title: title, subtitle: subtitle)
                } catch {
                    logger.error("Coinbase deposit failed", metadata: [
                        "error": "\(error)",
                        "amount": "\(amount.nativeAmount.formatted())",
                        "orderId": "\(operation.orderId ?? "nil")",
                    ])
                    ErrorReporting.captureError(error)
                    self?.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
                }
            }
        }
    }

    private func startPhantomDeposit(
        amount: ExchangedFiat,
        walletConnection: any TransactionSigning,
        onProceed: @escaping (AddMoneyProcessingInput) -> Void
    ) {
        let operation = PhantomDepositOperation(walletConnection: walletConnection)
        depositTask = Task { [weak self, operation] in
            self?.actionButtonState = .loading
            defer { self?.actionButtonState = .normal }
            do {
                // The wallet was connected on the education screen — sign only.
                try await operation.signAndSubmit(amount: amount)
                onProceed(.init(amount: amount, method: .phantom, depositRef: operation.submittedSignature))
            } catch is CancellationError {
                // User dismissed the Phantom flow — silent.
            } catch let DepositError.externalRejected(title, subtitle) {
                self?.dialogItem = .error(title: title, subtitle: subtitle)
            } catch {
                logger.error("Phantom deposit failed", metadata: [
                    "error": "\(error)",
                    "amount": "\(amount.nativeAmount.formatted())",
                ])
                ErrorReporting.captureError(error)
                self?.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
            }
        }
    }

    /// Cancels any in-flight deposit so its abandoned event loop cannot
    /// consume a later attempt's events from the shared single-consumer
    /// streams (`applePayEvents` / `deeplinkEvents`).
    func cancelInFlightDeposit() {
        depositTask?.cancel()
        depositTask = nil
    }

    private func computeAmount(using rate: Rate) -> ExchangedFiat? {
        guard let amount = amountValidator.validate(enteredAmount) else { return nil }
        return ExchangedFiat(
            nativeAmount: FiatAmount(value: amount, currency: rate.currency),
            rate: rate
        )
    }
}
