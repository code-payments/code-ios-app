//
//  ConvertConfirmationViewModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.convert-confirmation")

/// Confirms a conversion and submits it. A convert to Dollars is the existing
/// sell (source → USDF); a convert to another token is buy-with-currency
/// (source → token). Both spend the same source-denominated `amount` and carry
/// the same 1% source sell fee.
@Observable
@MainActor
final class ConvertConfirmationViewModel {

    @ObservationIgnored let sourceMint: PublicKey
    @ObservationIgnored let destinationMint: PublicKey
    @ObservationIgnored let destinationName: String
    /// The source amount being converted, denominated in the source token.
    @ObservationIgnored let amount: ExchangedFiat
    /// The source pool's sell fee in basis points; nil falls back to 100 (1%).
    @ObservationIgnored let sellFeeBps: Int?
    @ObservationIgnored let pinnedState: VerifiedState

    var dialogItem: DialogItem?
    private(set) var actionButtonState: ButtonState = .normal
    var canDismissSheet: Bool = false

    /// True when converting straight to Dollars (USDF) — the sell path.
    var isToDollars: Bool { destinationMint == .usdf }

    /// True when converting *from* Dollars — a buy paid from reserves.
    var isFromDollars: Bool { sourceMint == .usdf }

    var canPerformAction: Bool { !pinnedState.isStale }

    /// Every conversion carries the 1% fee, including from Dollars. USDF has no
    /// `sellFeeBps` of its own, so it falls back to the 100 bps default.
    var fee: ExchangedFiat {
        amount.launchpadSellFee(bps: UInt64(max(0, sellFeeBps ?? 100)))
    }

    /// Formats the fee, prefixing "~" when non-zero but below display precision.
    var feeFormatted: String {
        let prefix = fee.isApproximatelyZero() ? "~" : ""
        return "\(prefix)\(fee.nativeAmount.formatted())"
    }

    /// What the conversion nets after the source sell fee.
    var amountAfterFee: ExchangedFiat {
        amount.subtractingFee(fee.onChainAmount)
    }

    // MARK: - Init -

    init(sourceMint: PublicKey, destinationMint: PublicKey, destinationName: String, amount: ExchangedFiat, sellFeeBps: Int?, pinnedState: VerifiedState) {
        self.sourceMint       = sourceMint
        self.destinationMint  = destinationMint
        self.destinationName  = destinationName
        self.amount           = amount
        self.sellFeeBps       = sellFeeBps
        self.pinnedState      = pinnedState
    }

    // MARK: - Actions -

    func performConvert(session: Session, router: AppRouter) {
        guard actionButtonState == .normal else { return }
        actionButtonState = .loading

        Task {
            do {
                let swapId: SwapId
                if isToDollars {
                    // Token → Dollars is the sell path.
                    swapId = try await session.sell(amount: amount, verifiedState: pinnedState, in: sourceMint)
                } else if isFromDollars {
                    // Dollars → a token is a buy paid from reserves.
                    swapId = try await session.buy(amount: amount, verifiedState: pinnedState, of: destinationMint)
                } else {
                    // Token → token is buy-with-currency.
                    swapId = try await session.buy(amount: amount, with: sourceMint, verifiedState: pinnedState, of: destinationMint)
                }
                actionButtonState = .normal
                router.pushAny(ConvertFlowPath.processing(
                    swapId: swapId,
                    destinationMint: destinationMint,
                    destinationName: destinationName,
                    amount: amountAfterFee
                ))
            } catch Session.Error.verifiedStateStale {
                // Session.assertFresh already logged this. The pin can't refresh
                // here (quarks are tied to it), so give the user a way out.
                actionButtonState = .normal
                dialogItem = .error(
                    title: "Rate Expired",
                    subtitle: "This quote is no longer valid. Please go back and try again."
                )
            } catch Session.Error.insufficientBalance {
                actionButtonState = .normal
                dialogItem = .error(
                    title: "Insufficient Balance",
                    subtitle: "You don't have enough to convert this amount. Please go back and enter a smaller amount."
                )
            } catch {
                logger.error("Failed to convert currency", metadata: [
                    "sourceMint": "\(sourceMint.base58)",
                    "destinationMint": "\(destinationMint.base58)",
                    "amount": "\(amount.nativeAmount.formatted())",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to convert currency",
                    metadata: [
                        "sourceMint": sourceMint.base58,
                        "destinationMint": destinationMint.base58,
                        "amount": amount.nativeAmount.formatted(),
                        "fee": fee.nativeAmount.formatted(),
                        "quarks": "\(amount.onChainAmount.quarks)",
                    ],
                    userFacing: true
                )
                actionButtonState = .normal
                showErrorDialog(error: error)
            }
        }
    }

    // MARK: - Dialogs -

    private func showErrorDialog(error: Error) {
        let title: String
        let subtitle: String

        switch error {
        case ErrorSwap.denied(_, let kinds, _) where kinds.contains(.insufficientSellFee):
            title = "Amount Too Small"
            subtitle = "The amount you entered is too small to cover the required transaction fee. Please enter a larger amount"

        default:
            title = "Unable to Convert Currency"
            subtitle = "We couldn't complete your conversion. Please try again or contact support at support@flipcash.com if the issue persists."
        }

        dialogItem = .error(title: title, subtitle: subtitle) {
            .okay(kind: .destructive) { [weak self] in
                self?.actionButtonState = .normal
            }
        }
    }
}
