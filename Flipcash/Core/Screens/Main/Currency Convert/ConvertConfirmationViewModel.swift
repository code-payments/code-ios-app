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

    /// The conversion fee. From Dollars it's a flat 1% added on top of the
    /// purchase (a reserves buy — the server splits it off on-chain); token
    /// conversions carry the source pool's sell fee taken out of the amount.
    var fee: ExchangedFiat {
        let bps: UInt64 = isFromDollars ? 100 : UInt64(max(0, sellFeeBps ?? 100))
        return amount.launchpadSellFee(bps: bps)
    }

    /// Formats the fee, prefixing "~" when non-zero but below display precision.
    var feeFormatted: String {
        let prefix = fee.isApproximatelyZero() ? "~" : ""
        return "\(prefix)\(fee.nativeAmount.formatted())"
    }

    /// What the conversion nets. From Dollars the entered amount is received in
    /// full (the fee is on top); otherwise the source sell fee comes out.
    var amountAfterFee: ExchangedFiat {
        isFromDollars ? amount : amount.subtractingFee(fee.onChainAmount)
    }

    /// The total source debited ("You Convert"). From Dollars it's the purchase
    /// plus the on-top fee; otherwise the entered amount already is the debit.
    var totalDebited: ExchangedFiat {
        isFromDollars ? amount.adding(fee) : amount
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
                    // Dollars → a token is a buy paid from reserves. `amount` is
                    // the net purchase; the 1% fee is added on top and split off
                    // on-chain, so the debit is `amount + fee`.
                    swapId = try await session.buy(amount: amount, feeAmount: fee, verifiedState: pinnedState, of: destinationMint)
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
