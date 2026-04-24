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
    var path: [WithdrawNavigationPath] = []
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
        // Source rate and bonded supply from the pinned proof so the quarks the
        // server validates against `pinnedState.rateProto`/`reserveProto` match
        // what we computed. Live cache values drift as the stream delivers new
        // proofs mid-entry, producing native/quark mismatches.
        //
        // Unlike Buy/Sell, the pin isn't resolved at sheet open — it's fetched
        // asynchronously per-balance in `selectCurrency(_:)`, so there's a
        // window where `selectedBalance != nil && pinnedState == nil`. Falling
        // back to the live rate here lets the amount input show a preview
        // during that window. Submission itself is still gated — see
        // `canCompleteWithdrawal`, which requires a non-stale `pinnedState`.
        let rate = pinnedState?.rate ?? ratesController.rateForEntryCurrency()

        // Only applies for bonded tokens
        if mint != .usdf {
            guard let supplyQuarks = pinnedState?.supplyFromBonding ?? selectedBalance.stored.supplyFromBonding else {
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

        guard let pinned = pinnedState, !pinned.isStale else {
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
        // Match `enteredFiat`'s rate source so the displayed cap uses the same
        // rate the entered amount is computed against.
        let rate = pinnedState?.rate ?? ratesController.rateForEntryCurrency()
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

        // Prefer the pinned bonding supply for the same reason enteredFiat does
        // — fee math against a drifted supply would misreport the on-chain fee
        // equivalent.
        guard let supplyQuarks = pinnedState?.supplyFromBonding ?? selectedBalance.stored.supplyFromBonding else {
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
    
    @ObservationIgnored private var amountToWithdraw: ExchangedFiat?
    /// Observed (no `@ObservationIgnored`) so the submit button's enabled state
    /// re-evaluates when the async `pinFetchTask` resolves the pin.
    var pinnedState: VerifiedState?
    @ObservationIgnored private var pinFetchTask: Task<Void, Never>?
    @ObservationIgnored private let isPresented: Binding<Bool>
    @ObservationIgnored private let container: Container
    @ObservationIgnored private let client: Client
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let ratesController: RatesController
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self.isPresented     = isPresented
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
    
    private func completeWithdrawal() {
        guard let amountToWithdraw, let destinationMetadata else {
            return
        }

        guard let verifiedState = pinnedState else {
            return
        }

        let fee: TokenAmount
        if amountToWithdraw.mint == .usdf {
            fee = destinationMetadata.fee
        } else {
            fee = exchangedFee?.onChainAmount ?? .zero(mint: .usdf)
        }

        withdrawButtonState = .loading
        Task {
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
    
    // MARK: - Actions -

    func selectCurrency(_ balance: ExchangedBalance) {
        selectedBalance = balance
        enteredAmount = ""
        enteredAddress = ""
        destinationMetadata = nil
        withdrawButtonState = .normal
        pinnedState = nil
        pushEnterAmountScreen()

        refreshPin(for: balance.stored.mint)
    }

    /// Called when `ratesController.entryCurrency` changes while the screen
    /// is open. Re-fetches the pin for the currently-selected balance
    /// against the new currency so the amount-entry screen updates instead
    /// of silently continuing to display the old currency's math.
    func rePinForEntryCurrency() {
        guard let mint = selectedBalance?.stored.mint else { return }
        if let pinned = pinnedState, pinned.currencyCode == ratesController.entryCurrency { return }
        pinnedState = nil
        refreshPin(for: mint)
    }

    private func refreshPin(for mint: PublicKey) {
        // Cancel any in-flight pin fetch so a stale result can't clobber the
        // current selection's pinnedState.
        pinFetchTask?.cancel()

        let currency = ratesController.entryCurrency
        pinFetchTask = Task {
            // currentPinnedState logs the nil-case itself.
            guard let pinned = await ratesController.currentPinnedState(for: currency, mint: mint) else {
                return
            }
            guard !Task.isCancelled else { return }
            pinnedState = pinned
        }
    }

    func amountEnteredAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }

        let result = session.hasSufficientFunds(for: exchangedFiat)

        // Use switch for exhaustive checking - compiler will error if new cases are added
        switch result {
        case .sufficient(let amountToSend):
            amountToWithdraw = amountToSend
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
        path = [.enterAmount]
    }
    
    func pushEnterAmountScreen() {
        path.append(.enterAmount)
    }
    
    private func pushEnterAddressScreen() {
        path.append(.enterAddress)
    }
    
    private func pushConfirmationScreen() {
        path.append(.confirmation)
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
                self?.isPresented.wrappedValue = false
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
