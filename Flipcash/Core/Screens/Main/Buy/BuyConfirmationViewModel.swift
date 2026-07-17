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

    var isUSDF: Bool { payment.mint == .usdf }

    var canPerformAction: Bool { !pinnedState.isStale }

    var feeBps: UInt64 { UInt64(max(0, payment.sellFeeBps ?? 100)) }

    var fee: ExchangedFiat {
        paymentAmount.launchpadSellFee(bps: feeBps)
    }

    /// Formats the fee, prefixing "~" when non-zero but below display precision.
    var feeFormatted: String {
        let prefix = fee.isApproximatelyZero() ? "~" : ""
        return "\(prefix)\(fee.nativeAmount.formatted())"
    }

    /// What the buy leg actually purchases — the gross debit minus the pool fee.
    var amountToBuy: ExchangedFiat {
        isUSDF ? paymentAmount : paymentAmount.subtractingFee(fee.onChainAmount)
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

    func buyAction(session: Session, router: AppRouter) async {
        // Re-entrancy guard: don't rely on the button disabling itself.
        guard actionButtonState == .normal else { return }

        // The entry cap is balance-only; the send limit is enforced here.
        let sendLimit = session.sendLimitFor(currency: paymentAmount.nativeAmount.currency) ?? .zero
        guard paymentAmount.nativeAmount.value <= sendLimit.maxPerDay.value else {
            logger.info("Buy rejected: amount exceeds limit", metadata: [
                "amount": "\(paymentAmount.nativeAmount.formatted())",
                "max_per_day": "\(sendLimit.maxPerDay.value)",
                "currency": "\(paymentAmount.nativeAmount.currency)",
            ])
            dialogItem = .error(
                title: "Transaction Limit Reached",
                subtitle: "You can only buy up to the transaction limit at a time"
            )
            return
        }

        switch session.hasSufficientFunds(for: paymentAmount) {
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

        logger.info("Buy maximum selected", metadata: [
            "paymentMint": "\(payment.mint.base58)",
            "previousQuarks": "\(paymentAmount.onChainAmount.quarks)",
            "balanceQuarks": "\(live.quarks)",
        ])

        paymentAmount = ExchangedFiat.compute(
            onChainAmount: TokenAmount(quarks: live.quarks, mint: payment.mint),
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
                swapId = try await session.buy(amount: paymentAmount, verifiedState: pinnedState, of: targetMint)
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
                metadata: ["targetMint": targetMint.base58, "paymentMint": payment.mint.base58]
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
