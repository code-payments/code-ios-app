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
    /// Pushes a sub-step onto the parent NavigationStack. Wired by
    /// `WithdrawScreen` to call `router.pushAny(_:on: .settings)`.
    @ObservationIgnored var pushSubstep: (WithdrawNavigationPath) -> Void = { _ in }

    var withdrawButtonState: ButtonState = .normal
    var kind: WithdrawKind?

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
        computeAmount(using: ratesController.rateForBalanceCurrency(), pinnedSupplyQuarks: nil)
    }

    /// Fee in the user's currency for the summary's "Less fee" line. Rounded
    /// half-up to currency precision so the implied fee on the amount screen
    /// (`minimumWithdrawAmount = displayFee + smallestUnit`) matches the
    /// summary verbatim — no rounding drift between the two screens.
    var displayFee: FiatAmount? {
        guard let enteredFiat, let fee = resolvedFee else { return nil }
        let feeInEntry = fee.usd.converting(to: enteredFiat.currencyRate)
        let rounded = feeInEntry.value.rounded(to: feeInEntry.currency.maximumFractionDigits)
        return FiatAmount(value: rounded, currency: feeInEntry.currency)
    }

    /// Net in the user's currency, derived as `entered − displayFee` so the
    /// three summary lines (Withdrawal amount, Less fee, Net amount) form a
    /// closed identity. Falls back to `entered` when there's no fee.
    var displayNet: FiatAmount? {
        guard let enteredFiat else { return nil }
        let entered = enteredFiat.nativeAmount
        guard let fee = displayFee else { return entered }
        return entered - fee
    }

    /// Smallest amount that yields at least one displayable unit of net after
    /// the fee. `displayFee + smallest_displayable_unit` in the user's currency.
    /// Display and the `isBelowMinimumWithdraw` gate use the same number by
    /// construction.
    var minimumWithdrawAmount: FiatAmount? {
        guard let displayFee else { return nil }
        let precision = displayFee.currency.maximumFractionDigits
        let smallestUnit = Decimal(sign: .plus, exponent: -precision, significand: 1)
        return FiatAmount(value: displayFee.value + smallestUnit, currency: displayFee.currency)
    }

    /// Compares the raw entered Decimal against `minimumWithdrawAmount`.
    /// Uses `Decimal(string:)` (always "." separator, matching the keypad's
    /// output and `EnterAmountView.isExceedingLimit`) instead of the
    /// locale-aware `NumberFormatter.decimal(from:)`, which on non-"."
    /// locales parses "0.69" as 0 and falsely fires the gate.
    var isBelowMinimumWithdraw: Bool {
        guard let minimum = minimumWithdrawAmount else { return false }
        guard let entered = Decimal(string: enteredAmount) else { return false }
        return entered < minimum.value
    }

    var withdrawableAmount: ExchangedFiat? {
        guard let enteredFiat else { return nil }
        guard let fee = resolvedFee, fee.onChain.quarks > 0 else {
            return enteredFiat
        }
        // subtractingFee would underflow TokenAmount; nil signals overflow.
        guard fee.onChain <= enteredFiat.onChainAmount else { return nil }
        return enteredFiat.subtractingFee(fee.onChain)
    }

    /// Withdrawal fee resolved against the entered mint. USDF withdrawals pay in
    /// USDF directly; bonded token withdrawals pay via the bonding curve, so the
    /// on-chain fee is in bonded tokens and needs the curve's USD valuation for
    /// any fiat arithmetic against the entered amount.
    private var resolvedFee: (onChain: TokenAmount, usd: FiatAmount)? {
        guard let enteredFiat else { return nil }
        let withdrawalFee = session.userFlags?.withdrawalFeeAmount ?? .zero(mint: .usdf)
        guard withdrawalFee.quarks > 0 else { return nil }
        if enteredFiat.mint == .usdf {
            return (
                onChain: withdrawalFee,
                usd: FiatAmount.usd(withdrawalFee.decimalValue)
            )
        }
        guard let exchangedFee else { return nil }
        return (onChain: exchangedFee.onChainAmount, usd: exchangedFee.usdfValue)
    }

    /// Gate for the Enter-Amount screen's Next button. Disables when the
    /// entered amount exceeds the displayed balance cap (so `EnterAmountView`
    /// turns the subtitle red). Below-fee entries keep the button enabled so
    /// `amountEnteredAction` can surface the dialog explaining the floor.
    var canProceedToAddress: Bool {
        guard enteredFiat != nil else { return false }
        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxWithdrawLimit.nativeAmount
        )
    }

    var canCompleteWithdrawal: Bool {
        guard
            let kind,
            let enteredFiat,
            enteredDestination != nil,
            let destinationMetadata,
            destinationMetadata.isValid
        else {
            return false
        }
        if !kind.acceptsTokenAccount && destinationMetadata.kind == .token {
            return false
        }
        switch session.hasSufficientFunds(for: enteredFiat) {
        case .sufficient:   return true
        case .insufficient: return false
        }
    }

    /// Post-fee on-chain token quantity in the destination mint, formatted with
    /// the mint's decimal scaling (e.g. 297_902_148_685 quarks → "29.7902148685"
    /// for a 10-decimal Jeffy token; 234_784 quarks → "0.234784" for a 6-decimal
    /// USDF). Used for both the summary's "Amount in <name>" row and the big
    /// "You Receive" box — same value, different framing.
    var youReceiveDisplayValue: String? {
        withdrawableAmount?.onChainAmount.decimalValue.formatted()
    }

    /// Logo URL for the You Receive box. For both kinds the logo comes from
    /// the destination mint's `MintMetadata.imageURL` — same `RemoteImage`
    /// path the rest of the app uses for token avatars.
    var destinationLogoURL: URL? {
        switch kind {
        case .sameMint(let balance):
            return balance.stored.imageURL
        case .usdfToUsdc:
            return MintMetadata.usdc.imageURL
        case .none:
            return nil
        }
    }

    /// Subtitle for the amount-entry screen. "Minimum withdrawal $X.XX" when
    /// the entered amount is at or below the fee, hinting at the floor without
    /// disabling Next — the gating dialog fires from `amountEnteredAction`.
    /// Otherwise the "Enter up to $Y.YY" balance-with-limit copy.
    var amountSubtitle: EnterAmountView.Subtitle {
        if isBelowMinimumWithdraw, let minimum = minimumWithdrawAmount {
            return .error("Minimum withdrawal \(minimum.formatted())")
        }
        return .balanceWithLimit(maxWithdrawLimit)
    }

    var maxWithdrawLimit: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: .usdf),
            rate: rate,
            supplyQuarks: nil
        )

        guard let mint = kind?.sourceMint else {
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

        guard let balance = kind?.balance else {
            return nil
        }

        guard let supplyQuarks = balance.stored.supplyFromBonding else {
            return nil
        }

        let withdrawalFee = session.userFlags?.withdrawalFeeAmount ?? .zero(mint: .usdf)
        guard withdrawalFee.quarks > 0 else { return nil }

        // Fee is charged in USDF, so use oneToOne
        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: withdrawalFee.decimalValue, currency: Rate.oneToOne.currency),
            rate: .oneToOne,
            mint: enteredFiat.mint,
            supplyQuarks: supplyQuarks,
            balance: balance.stored.usdf
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

        guard let mint = kind?.destinationMint else {
            return
        }

        Task {
            destinationMetadata = await client.fetchDestinationMetadata(destination: enteredDestination, mint: mint)
        }
    }

    /// Resolves the pin for the selected balance's mint and computes the
    /// submission amount against it — one fetch for both.
    func prepareSubmission() async -> (amount: ExchangedFiat, pinnedState: VerifiedState)? {
        guard let mint = kind?.sourceMint else { return nil }
        let currency = ratesController.balanceCurrency
        guard let pin = await ratesController.currentPinnedState(for: currency, mint: mint) else {
            return nil
        }
        guard let amount = computeAmount(using: pin.rate, pinnedSupplyQuarks: pin.supplyFromBonding) else {
            return nil
        }
        return (amount, pin)
    }

    /// Translates `enteredAmount` to an `ExchangedFiat` clamped to the on-chain
    /// balance. The clamp absorbs display-rounding overshoot (`.halfUp`
    /// formatter, `scaleUpInt` HALF_UP) so the submitted quarks can never
    /// exceed `balance.stored.quarks`.
    ///
    /// - Parameter pinnedSupplyQuarks: pass `nil` for the display preview
    ///   (falls back to live balance supply) and the pinned proof's supply
    ///   for submission.
    private func computeAmount(using rate: Rate, pinnedSupplyQuarks: UInt64?) -> ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let balance = kind?.balance else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        let mint = balance.stored.mint
        // ExchangedFiat.compute ignores supplyQuarks for USDF (no bonding curve);
        // bonded mints require it.
        let supplyQuarks: UInt64
        if mint == .usdf {
            supplyQuarks = 0
        } else {
            guard let bondedSupply = pinnedSupplyQuarks ?? balance.stored.supplyFromBonding else {
                return nil
            }
            supplyQuarks = bondedSupply
        }

        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: amount, currency: rate.currency),
            rate: rate,
            mint: mint,
            supplyQuarks: supplyQuarks,
            balance: balance.stored.usdf,
            tokenBalanceQuarks: balance.stored.quarks
        )
    }

    // MARK: - Actions -

    func selectCurrency(_ balance: ExchangedBalance) {
        let kindForBalance: WithdrawKind = balance.stored.mint == .usdf
            ? .usdfToUsdc(balance)
            : .sameMint(balance)
        self.kind = kindForBalance
        enteredAmount = ""
        enteredAddress = ""
        destinationMetadata = nil
        withdrawButtonState = .normal

        if kindForBalance.showsIntroScreen {
            pushIntroScreen()
        } else {
            pushEnterAmountScreen()
        }
    }

    func amountEnteredAction() {
        if isBelowMinimumWithdraw {
            showWithdrawalTooSmallError()
            return
        }

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
        dialogItem = .init(
            style: .destructive,
            title: "Are You Sure?",
            subtitle: "Withdrawals are irreversible and cannot be undone once initiated",
            dismissable: true,
            actions: {
                .destructive("Yes, Withdraw") { [weak self] in
                    self?.completeWithdrawal()
                };
                .cancel()
            }
        )
    }

    private func completeWithdrawal() {
        guard let kind, let destinationMetadata else { return }

        withdrawButtonState = .loading
        Task {
            guard let (amountToWithdraw, verifiedState) = await prepareSubmission() else {
                withdrawButtonState = .normal
                dialogItem = .staleRate
                return
            }

            let fee: TokenAmount
            if amountToWithdraw.mint == .usdf {
                fee = session.userFlags?.withdrawalFeeAmount ?? .zero(mint: .usdf)
            } else {
                fee = exchangedFee?.onChainAmount ?? .zero(mint: .usdf)
            }

            do {
                switch kind {
                case .sameMint:
                    try await session.withdraw(
                        exchangedFiat: amountToWithdraw,
                        verifiedState: verifiedState,
                        fee: fee,
                        to: destinationMetadata
                    )
                case .usdfToUsdc:
                    guard let destinationOwner = enteredDestination else {
                        withdrawButtonState = .normal
                        dialogItem = .somethingWentWrong
                        return
                    }
                    _ = try await client.withdrawAsUSDC(
                        amount: amountToWithdraw,
                        verifiedState: verifiedState,
                        destinationOwner: destinationOwner,
                        fee: fee,
                        sourceCluster: session.owner
                    )
                    session.updatePostTransaction()
                    Analytics.withdrawal(exchangedFiat: amountToWithdraw, successful: true, error: nil)
                }

                try await Task.delay(milliseconds: 500)
                withdrawButtonState = .success
                try await Task.delay(milliseconds: 500)
                showSuccessfulWithdrawalDialog()

            } catch Session.Error.verifiedStateStale {
                withdrawButtonState = .normal
                dialogItem = .staleRate
            } catch {
                // .usdfToUsdc bypasses Session and reports/emits analytics here;
                // .sameMint flows through Session.withdraw, which owns both.
                switch kind {
                case .usdfToUsdc:
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
                    Analytics.withdrawal(exchangedFiat: amountToWithdraw, successful: false, error: error)
                case .sameMint:
                    break
                }
                withdrawButtonState = .normal
                dialogItem = .somethingWentWrong
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

    // MARK: - Navigation -

    private func pushIntroScreen() {
        pushSubstep(.intro)
    }

    func pushEnterAmountScreen() {
        pushSubstep(.enterAmount)
    }

    private func pushEnterAddressScreen() {
        pushSubstep(.enterAddress)
    }

    private func pushConfirmationScreen() {
        pushSubstep(.confirmation)
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

    private func showWithdrawalTooSmallError() {
        dialogItem = .init(
            style: .destructive,
            title: "Withdrawal Amount Too Small",
            subtitle: "Your withdrawal amount is too small to cover the fee. Please try a different amount",
            dismissable: true
        ) {
            .okay(kind: .standard)
        }
    }
}

enum WithdrawNavigationPath {
    case intro
    case enterAmount
    case enterAddress
    case confirmation
}

enum WithdrawKind: Equatable {
    /// Source mint == destination mint. Legacy IntentWithdraw path.
    case sameMint(ExchangedBalance)

    /// USDF balance → USDC wallet via Coinbase Stable Swapper.
    case usdfToUsdc(ExchangedBalance)

    var balance: ExchangedBalance {
        switch self {
        case .sameMint(let b), .usdfToUsdc(let b): return b
        }
    }

    var sourceMint: PublicKey { balance.stored.mint }

    /// Mint that lands in the destination wallet. Used by `fetchDestinationMetadata`
    /// so the server-side ATA existence check runs against the right mint.
    var destinationMint: PublicKey {
        switch self {
        case .sameMint(let b): return b.stored.mint
        case .usdfToUsdc:      return .usdc
        }
    }

    /// Name shown on the address screen and the summary's "You Receive" box.
    /// Always the *destination* currency.
    var destinationCurrencyName: String {
        switch self {
        case .sameMint(let b): return b.stored.name
        case .usdfToUsdc:      return "USDC"
        }
    }

    /// Whether `accountType == .token` is accepted at the address pill. The
    /// usdfToUsdc RPC requires a 32-byte owner pubkey — token accounts can't
    /// be resolved server-side.
    var acceptsTokenAccount: Bool {
        switch self {
        case .sameMint:    return true
        case .usdfToUsdc:  return false
        }
    }

    /// Whether the picker pushes the intro screen before amount entry.
    var showsIntroScreen: Bool {
        switch self {
        case .sameMint:    return false
        case .usdfToUsdc:  return true
        }
    }
}
