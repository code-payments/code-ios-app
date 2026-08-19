//
//  BuyConfirmationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.buy-confirmation")

@Observable
@MainActor
final class BuyConfirmationViewModel {

    @ObservationIgnored let targetMint: PublicKey
    @ObservationIgnored let targetName: String
    @ObservationIgnored let payment: StoredBalance
    @ObservationIgnored let pinnedState: VerifiedState

    var dialogItem: DialogItem?
    private(set) var actionButtonState: ButtonState = .normal
    /// Gross debit in the payment token. Mutated in place by Buy Maximum.
    private(set) var paymentAmount: ExchangedFiat
    /// Icon for the You Receive row, resolved from cached mint metadata.
    private(set) var targetImageURL: URL?

    @ObservationIgnored private var hasCheckedFundsOnAppear = false

    var isUSDF: Bool { payment.mint == .usdf }

    var canPerformAction: Bool { !pinnedState.isStale }

    /// The USDF reserves buy carries a flat 1% fee added on top of the purchase;
    /// the token-funded path uses the payment pool's own sell fee.
    var feeBps: UInt64 { isUSDF ? 100 : UInt64(max(0, payment.sellFeeBps ?? 100)) }

    /// New-UI USDF reserves buys collect a 1% fee (split off on-chain via the
    /// server's fee destination). Old UI leaves the reserves buy fee-free.
    private var chargesUSDFFee: Bool { isUSDF && BetaFlags.shared.hasEnabled(.newUI) }

    /// Whether a fee row is shown and collected. Token-funded buys always carry
    /// the implicit sell fee; USDF buys only in the new UI.
    var chargesFee: Bool { !isUSDF || chargesUSDFFee }

    var fee: ExchangedFiat {
        // Same call both ways: for USDF `paymentAmount` is the net purchase so
        // this is 1% on top; for tokens it's the gross debit so this is the
        // implicit sell fee taken out.
        paymentAmount.launchpadSellFee(bps: feeBps)
    }

    /// Formats the fee, prefixing "~" when non-zero but below display precision.
    var feeFormatted: String {
        let prefix = fee.isApproximatelyZero() ? "~" : ""
        return "\(prefix)\(fee.nativeAmount.formatted())"
    }

    /// What the buy leg actually purchases ("You Get"). For USDF the entered
    /// amount *is* the net purchase (fee added on top); for tokens it's the
    /// gross debit minus the implicit sell fee.
    var amountToBuy: ExchangedFiat {
        guard chargesFee else { return paymentAmount }
        return isUSDF ? paymentAmount : paymentAmount.subtractingFee(fee.onChainAmount)
    }

    /// The amount actually removed from the balance ("You Pay"). For USDF it's
    /// the net purchase plus the on-top fee; for tokens `paymentAmount` already
    /// is the gross debit.
    var grossDebit: ExchangedFiat {
        guard chargesFee else { return paymentAmount }
        return isUSDF ? paymentAmount.adding(fee) : paymentAmount
    }

    init(targetMint: PublicKey, targetName: String, payment: StoredBalance, paymentAmount: ExchangedFiat, pinnedState: VerifiedState) {
        self.targetMint = targetMint
        self.targetName = targetName
        self.payment = payment
        self.paymentAmount = paymentAmount
        self.pinnedState = pinnedState
    }

    // MARK: - Actions

    func loadTargetImage(session: Session) async {
        targetImageURL = try? await session.fetchMintMetadata(mint: targetMint).imageURL
    }

    /// Surfaces the insufficient-balance sheet when the amount pushed onto this
    /// screen already exceeds the payment balance, at most once per screen.
    func presentInsufficientBalanceIfNeeded(session: Session) {
        guard !hasCheckedFundsOnAppear else { return }
        hasCheckedFundsOnAppear = true

        switch session.hasSufficientFunds(for: grossDebit) {
        case .sufficient:
            break
        case .insufficient:
            logger.info("Buy gated on appear: insufficient balance", metadata: [
                "paymentMint": "\(payment.mint.base58)",
                "amountQuarks": "\(grossDebit.onChainAmount.quarks)",
                "balanceQuarks": "\(session.balance(for: payment.mint)?.quarks ?? 0)",
            ])
            showInsufficientBalance(session: session)
        }
    }

    func buyAction(session: Session, router: AppRouter) async {
        // Re-entrancy guard: don't rely on the button disabling itself.
        guard actionButtonState == .normal else { return }

        // The entry cap is balance-only; the send limit is enforced here on the
        // full debit (purchase + any on-top fee).
        let sendLimit = session.sendLimitFor(currency: grossDebit.nativeAmount.currency) ?? .zero
        guard grossDebit.nativeAmount.value <= sendLimit.maxPerDay.value else {
            logger.info("Buy rejected: amount exceeds limit", metadata: [
                "amount": "\(grossDebit.nativeAmount.formatted())",
                "max_per_day": "\(sendLimit.maxPerDay.value)",
                "currency": "\(grossDebit.nativeAmount.currency)",
            ])
            dialogItem = .error(
                title: "Transaction Limit Reached",
                subtitle: "You can only buy up to the transaction limit at a time"
            )
            return
        }

        switch session.hasSufficientFunds(for: grossDebit) {
        case .sufficient:
            // Submit the pin-computed amount, not the gate's clamp — quarks
            // must stay tied to the pinned proof. A tolerance overshoot is
            // clamped against the pin inside `Session.buy`.
            await submit(session: session, router: router)
        case .insufficient:
            logger.info("Buy gated: insufficient balance", metadata: [
                "paymentMint": "\(payment.mint.base58)",
                "amountQuarks": "\(paymentAmount.onChainAmount.quarks)",
                "balanceQuarks": "\(session.balance(for: payment.mint)?.quarks ?? 0)",
            ])
            showInsufficientBalance(session: session)
        }
    }

    /// Recomputes the summary in place to spend the entire payment balance —
    /// the user still confirms with Buy.
    func buyMaximum(session: Session) {
        guard let live = session.balance(for: payment.mint) else { return }
        // USDF needs no reserve supply; bonded mints do (a nil supply would
        // value the balance as zero).
        let supply = pinnedState.supplyFromBonding
        guard isUSDF || supply != nil else { return }

        // With an on-top USDF fee the debit is `net + net·bps/10⁴`, so the net
        // purchase must be shrunk to keep the whole debit within the balance:
        // net = ⌊balance · 10⁴ / (10⁴ + bps)⌋. Split-divide to avoid overflow.
        let maxQuarks: UInt64
        if chargesUSDFFee {
            let denom = 10_000 + feeBps
            maxQuarks = live.quarks / denom * 10_000 + (live.quarks % denom) * 10_000 / denom
        } else {
            maxQuarks = live.quarks
        }

        logger.info("Buy maximum selected", metadata: [
            "paymentMint": "\(payment.mint.base58)",
            "previousQuarks": "\(paymentAmount.onChainAmount.quarks)",
            "balanceQuarks": "\(live.quarks)",
            "maxQuarks": "\(maxQuarks)",
        ])

        paymentAmount = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: maxQuarks, mint: payment.mint),
            rate: pinnedState.rate,
            supplyQuarks: supply
        )
    }

    private func submit(session: Session, router: AppRouter) async {
        actionButtonState = .loading
        do {
            let swapId: SwapId
            let swapType: SwapType
            if isUSDF {
                Analytics.buttonTapped(name: .buyWithReserves)
                // `paymentAmount` is the net purchase; the fee is added on top
                // and split off on-chain, so the debit is `paymentAmount + fee`.
                swapId = try await session.buy(
                    amount: paymentAmount,
                    feeAmount: chargesFee ? fee : nil,
                    verifiedState: pinnedState,
                    of: targetMint
                )
                swapType = .buyWithReserves
            } else {
                Analytics.buttonTapped(name: .buyWithCurrency)
                swapId = try await session.buy(amount: paymentAmount, with: payment.mint, verifiedState: pinnedState, of: targetMint)
                swapType = .buyWithCurrency
            }
            actionButtonState = .normal
            router.pushAny(BuyFlowPath.processing(
                swapId: swapId,
                targetMint: targetMint,
                currencyName: targetName,
                amount: amountToBuy,
                swapType: swapType
            ))
        } catch Session.Error.insufficientBalance {
            // Race: the balance gate said OK but the reserves buy disagreed.
            actionButtonState = .normal
            session.dialogItem = .noBalance(subtitle: AddMoneyContext.buyCurrency.noBalanceSubtitle) {
                router.presentAddMoney(.buyCurrency, source: .buyShortfall)
            }
        } catch Session.Error.verifiedStateStale {
            // Session.assertFresh already logged this. The pin can't refresh
            // on this screen (quarks are tied to it), so give the user a way
            // out instead of a silently disabled button.
            actionButtonState = .normal
            dialogItem = .error(
                title: "Rate Expired",
                subtitle: "This quote is no longer valid. Please go back and select the payment currency again."
            )
        } catch {
            logger.error("Failed to buy currency from BuyConfirmationScreen", metadata: [
                "targetMint": "\(targetMint.base58)",
                "paymentMint": "\(payment.mint.base58)",
                "amount": "\(paymentAmount.nativeAmount.formatted())",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(
                error,
                reason: "Failed to buy currency from BuyConfirmationScreen",
                metadata: ["targetMint": targetMint.base58, "paymentMint": payment.mint.base58],
                userFacing: true
            )
            actionButtonState = .normal
            // A submit failure can land after the user popped this screen —
            // `session.dialogItem` renders in `DialogWindow` above every
            // sheet, so the error survives the view's teardown.
            session.dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again later")
        }
    }

    // MARK: - Dialogs

    private func showInsufficientBalance(session: Session) {
        dialogItem = .info(
            title: isUSDF ? "Insufficient Balance" : "Insufficient Balance After Fees",
            subtitle: "Switch to maximum amount, or go back and enter a smaller amount"
        ) {
            .standard("Buy Maximum Amount") { [weak self] in
                self?.buyMaximum(session: session)
            };
            .dismiss(kind: .subtle)
        }
    }
}
