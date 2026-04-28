//
//  WithdrawViewModel.swift
//  Code
//
//  Created by Dima Bart on 2025-05-15.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor @Observable
class WithdrawViewModel {
    /// Tracks which sub-step screens have been pushed. Mirrors the
    /// `WithdrawNavigationPath` items the model has appended to the parent
    /// navigation stack via the `pushSubstep` callback. Used by
    /// `popToEnterAmount` to compute how many items to pop.
    @ObservationIgnored private var substepStack: [WithdrawNavigationPath] = []

    /// Pushes a sub-step onto the parent NavigationStack. Wired by
    /// `WithdrawScreen` to call `router.pushAny(_:on: .settings)`.
    @ObservationIgnored var pushSubstep: (WithdrawNavigationPath) -> Void = { _ in }

    /// Pops the given number of items from the parent NavigationStack.
    /// Wired by `WithdrawScreen` to call `router.popLast(_:on: .settings)`.
    @ObservationIgnored var popSubsteps: (Int) -> Void = { _ in }

    var withdrawButtonState: ButtonState = .normal
    var selectedBalance: ExchangedBalance?
    var enteredAmount: String = ""
    var enteredAddress: String = "" {
        didSet {
            if enteredDestination != nil {
                fetchDestinationMetadata()
            }
        }
    }

    var destinationMetadata: DestinationMetadata?
    var dialogItem: DialogItem?
    var enteredDestination: PublicKey? {
        try? PublicKey(base58: enteredAddress)
    }

    var enteredFiat: ExchangedFiat? {
        computeAmount(using: ratesController.rateForEntryCurrency(), pinnedSupplyQuarks: nil)
    }

    var displayFee: FiatAmount? {
        guard let enteredFiat, let withdrawableAmount else {
            return nil
        }
        let entered = enteredFiat.nativeAmount
        let withdrawable = withdrawableAmount.nativeAmount
        guard entered.currency == withdrawable.currency, entered >= withdrawable else {
            return nil
        }
        return entered - withdrawable
    }

    /// Returns the amount by which the fee exceeds the entered amount, or nil if the fee is covered.
    /// Used by `completeWithdrawalAction` to block withdrawals where the initialization fee exceeds the amount,
    /// and by the summary screen to display the negative delta.
    var negativeWithdrawableAmount: FiatAmount? {
        guard let enteredFiat, let destinationMetadata, destinationMetadata.requiresInitialization else {
            return nil
        }
        guard let fee = resolvedFee else { return nil }
        guard fee.onChain >= enteredFiat.onChainAmount else { return nil }
        return (fee.usd - enteredFiat.usdfValue).converting(to: enteredFiat.currencyRate)
    }

    var withdrawableAmount: ExchangedFiat? {
        guard let enteredFiat, let destinationMetadata else { return nil }
        guard destinationMetadata.requiresInitialization, destinationMetadata.fee.quarks > 0 else {
            return enteredFiat
        }
        guard let fee = resolvedFee else { return nil }
        // subtractingFee would underflow TokenAmount; nil signals overflow.
        guard fee.onChain <= enteredFiat.onChainAmount else { return nil }
        return enteredFiat.subtractingFee(fee.onChain)
    }

    /// Destination fee resolved against the entered mint. USDF users pay in
    /// USDC directly; bonded users pay via the bonding curve, so the on-chain
    /// fee is in bonded tokens and needs the curve's USD valuation for any
    /// fiat arithmetic against the entered amount.
    private var resolvedFee: (onChain: TokenAmount, usd: FiatAmount)? {
        guard let enteredFiat, let destinationMetadata, destinationMetadata.fee.quarks > 0 else {
            return nil
        }
        if enteredFiat.mint == .usdf {
            return (
                onChain: destinationMetadata.fee,
                usd: FiatAmount.usd(destinationMetadata.fee.decimalValue)
            )
        }
        guard let exchangedFee else { return nil }
        return (onChain: exchangedFee.onChainAmount, usd: exchangedFee.usdfValue)
    }

    /// Gate for the Enter-Amount screen's Next button. Disables when the
    /// entered amount exceeds the displayed balance cap so `EnterAmountView`
    /// turns the subtitle red.
    var canProceedToAddress: Bool {
        guard enteredFiat != nil else { return false }
        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxWithdrawLimit.nativeAmount
        )
    }

    var canCompleteWithdrawal: Bool {
        guard
            let enteredFiat = enteredFiat,
            let _ = enteredDestination,
            let destinationMetadata = destinationMetadata,
            destinationMetadata.isValid
        else {
            return false
        }

        switch session.hasSufficientFunds(for: enteredFiat) {
        case .sufficient:
            return true
        case .insufficient:
            return false
        }
    }

    var withdrawTitle: String {
        if let balance = selectedBalance {
            return "Withdraw \(balance.stored.name)"
        } else {
            return "Withdraw"
        }
    }

    var maxWithdrawLimit: ExchangedFiat {
        let rate = ratesController.rateForEntryCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )

        guard let mint = selectedBalance?.stored.mint else {
            return zero
        }

        guard let balance = session.balance(for: mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: rate)
    }

    private var exchangedFee: ExchangedFiat? {
        guard let enteredFiat = enteredFiat else {
            return nil
        }

        guard let selectedBalance else {
            return nil
        }

        guard let supplyQuarks = selectedBalance.stored.supplyFromBonding else {
            return nil
        }

        guard let destinationMetadata else {
            return nil
        }

        // Fee is charged in USDC, so use oneToOne
        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: destinationMetadata.fee.decimalValue, currency: Rate.oneToOne.currency),
            rate: .oneToOne,
            mint: enteredFiat.mint,
            supplyQuarks: supplyQuarks,
            balance: selectedBalance.stored.usdf
        )
    }

    /// Set by `WithdrawScreen` from `@Environment(\.dismiss)` once the view
    /// is on screen. Invoked by the success dialog to unwind the entire flow.
    @ObservationIgnored var onComplete: () -> Void = {}
    @ObservationIgnored private let container: Container
    @ObservationIgnored private let client: Client
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.container       = container
        self.client          = container.client
        self.session         = sessionContainer.session
        self.ratesController = sessionContainer.ratesController
    }

    // MARK: - Metadata -

    private func fetchDestinationMetadata() {
        guard let enteredDestination else {
            return
        }

        guard let mint = selectedBalance?.stored.mint else {
            return
        }

        Task {
            destinationMetadata = await client.fetchDestinationMetadata(destination: enteredDestination, mint: mint)
        }
    }

    /// Resolves the pin for the selected balance's mint and computes the
    /// submission amount against it — one fetch for both.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let mint = selectedBalance?.stored.mint else { return nil }
        let currency = ratesController.entryCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: mint) else {
            return nil
        }
        guard let amount = computeAmount(using: pin.rate, pinnedSupplyQuarks: pin.supplyFromBonding) else {
            return nil
        }
        return (amount, pin)
    }

    /// Preview passes `nil` for `pinnedSupplyQuarks` (falls back to live balance);
    /// submit passes the pinned supply so rate and supply come from one proof.
    private func computeAmount(using rate: Rate, pinnedSupplyQuarks: UInt64?) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let selectedBalance else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        let mint = selectedBalance.stored.mint

        // Only applies for bonded tokens
        if mint != .usdf {
            guard let supplyQuarks = pinnedSupplyQuarks ?? selectedBalance.stored.supplyFromBonding else {
                return nil
            }

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
            // Synthesize so the amount screen's `canProceedToAddress` flips
            // false and `EnterAmountView` turns the subtitle red.
            return ExchangedFiat(
                onChainAmount: TokenAmount(
                    quarks: selectedBalance.stored.quarks + 1,
                    mint: mint
                ),
                nativeAmount: entered,
                currencyRate: rate
            )
        } else {
            return ExchangedFiat(
                nativeAmount: FiatAmount(value: amount, currency: rate.currency),
                rate: rate
            )
        }
    }

    // MARK: - Actions -

    func selectCurrency(_ balance: ExchangedBalance) {
        selectedBalance = balance
        enteredAmount = ""
        enteredAddress = ""
        destinationMetadata = nil
        withdrawButtonState = .normal
        pushEnterAmountScreen()
    }

    func amountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        let result = session.hasSufficientFunds(for: exchangedFiat)

        // Use switch for exhaustive checking - compiler will error if new cases are added
        switch result {
        case .sufficient:
            pushEnterAddressScreen()

        case .insufficient:
            showInsufficientBalanceError()
        }
    }

    func addressEnteredAction() {
        pushConfirmationScreen()
    }

    func completeWithdrawalAction() {
        guard negativeWithdrawableAmount == nil else {
            dialogItem = .init(
                style: .destructive,
                title: "Withdrawal Amount Too Small",
                subtitle: "Your withdrawal amount is too small to cover the one time fee. Please try a different amount",
                dismissable: true
            ) {
                .okay(kind: .standard) { [weak self] in
                    self?.resetEnteredAmount()
                    self?.popToEnterAmount()
                }
            }
            return
        }

        dialogItem = .init(
            style: .destructive,
            title: "Are You Sure?",
            subtitle: "Withdrawals are irreversible and cannot be undone once initiated",
            dismissable: true,
            actions: {
                .destructive("Withdraw") { [weak self] in
                    self?.completeWithdrawal()
                };
                .cancel()
            }
        )
    }

    private func completeWithdrawal() {
        guard let destinationMetadata else {
            return
        }

        withdrawButtonState = .loading
        Task {
            guard let (amountToWithdraw, verifiedState) = await prepareSubmission() else {
                withdrawButtonState = .normal
                dialogItem = .staleRate
                return
            }

            let fee: TokenAmount
            if amountToWithdraw.mint == .usdf {
                fee = destinationMetadata.fee
            } else {
                fee = exchangedFee?.onChainAmount ?? .zero(mint: .usdf)
            }

            do {
                try await session.withdraw(
                    exchangedFiat: amountToWithdraw,
                    verifiedState: verifiedState,
                    fee: fee,
                    to: destinationMetadata
                )

                try await Task.delay(milliseconds: 500)
                withdrawButtonState = .success

                try await Task.delay(milliseconds: 500)
                showSuccessfulWithdrawalDialog()

            } catch Session.Error.verifiedStateStale {
                // Session.assertFresh already logged this. Reset button only.
                withdrawButtonState = .normal
            } catch {
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to withdraw",
                    metadata: [
                        "mint": amountToWithdraw.mint.base58,
                        "amount": amountToWithdraw.nativeAmount.formatted(),
                        "quarks": "\(amountToWithdraw.onChainAmount.quarks)",
                        "fee": "\(fee.quarks)",
                        "destination": destinationMetadata.destination.token.base58,
                        "requiresInit": "\(destinationMetadata.requiresInitialization)",
                    ]
                )
                withdrawButtonState = .normal
            }
        }
    }

    func pasteFromClipboardAction() {
        guard
            let string = UIPasteboard.general.string,
            let address = try? PublicKey(base58: string)
        else {
            return
        }

        enteredAddress = address.base58
    }

    // MARK: - Reset -

    private func resetEnteredAmount() {
        enteredAmount = ""
    }

    // MARK: - Navigation -

    private func popToEnterAmount() {
        // Pop everything above `.enterAmount`, leaving it as the top substep.
        // If we're already there or the stack is empty, this is a no-op.
        guard let firstAmountIndex = substepStack.firstIndex(of: .enterAmount) else {
            return
        }
        let popsNeeded = substepStack.count - (firstAmountIndex + 1)
        guard popsNeeded > 0 else { return }
        popSubsteps(popsNeeded)
        substepStack.removeLast(popsNeeded)
    }

    func pushEnterAmountScreen() {
        pushSubstep(.enterAmount)
        substepStack.append(.enterAmount)
    }

    private func pushEnterAddressScreen() {
        pushSubstep(.enterAddress)
        substepStack.append(.enterAddress)
    }

    private func pushConfirmationScreen() {
        pushSubstep(.confirmation)
        substepStack.append(.confirmation)
    }

    // MARK: - Dialogs -

    private func showSuccessfulWithdrawalDialog() {
        dialogItem = .init(
            style: .success,
            title: "Withdrawal Successful",
            subtitle: "Your withdrawal has been processed. It may take a few minutes for your funds to show up in your destination wallet.",
            dismissable: false
        ) {
            .okay(kind: .standard) { [weak self] in
                self?.onComplete()
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

enum WithdrawNavigationPath {
    case enterAmount
    case enterAddress
    case confirmation
}
