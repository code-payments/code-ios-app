//
//  CurrencySellConfirmationViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@Observable
class CurrencySellConfirmationViewModel {
    @ObservationIgnored let mint: PublicKey
    @ObservationIgnored let amount: ExchangedFiat
    @ObservationIgnored let pinnedState: VerifiedState
    /// The pool's sell fee in basis points; nil falls back to the launchpad
    /// default (100).
    @ObservationIgnored let sellFeeBps: Int?

    var dialogItem: DialogItem?
    private(set) var actionButtonState: ButtonState = .normal
    /// Swap id of a successfully submitted sell. The confirmation screen observes this to push the processing screen.
    var pendingSwapId: SwapId?

    var canDismissSheet: Bool = false

    var canPerformAction: Bool {
        !pinnedState.isStale
    }

    var fee: ExchangedFiat {
        amount.launchpadSellFee(bps: UInt64(max(0, sellFeeBps ?? 100)))
    }

    /// Formats the fee for display, prefixing with "~" when the value is
    /// too small for the currency's display precision (e.g. "~$0.00" for USD,
    /// "~¥0" for JPY) to indicate a non-zero but negligible fee.
    var feeFormatted: String {
        let prefix = fee.isApproximatelyZero() ? "~" : ""
        return "\(prefix)\(fee.nativeAmount.formatted())"
    }

    var amountAfterFee: ExchangedFiat {
        amount.subtractingFee(fee.onChainAmount)
    }

    // MARK: - Init -

    init(mint: PublicKey, amount: ExchangedFiat, pinnedState: VerifiedState, sellFeeBps: Int? = nil) {
        self.mint        = mint
        self.amount      = amount
        self.pinnedState = pinnedState
        self.sellFeeBps  = sellFeeBps
    }
    
    // MARK: - Actions -

    func performSell(using session: Session) {
        actionButtonState = .loading

        Task {
            do {
                let swapId = try await session.sell(amount: amount, verifiedState: pinnedState, in: mint)
                pendingSwapId = swapId
            } catch Session.Error.verifiedStateStale {
                // Session.assertFresh already logged this. Reset button only.
                actionButtonState = .normal
            } catch {
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to sell currency",
                    metadata: [
                        "mint": mint.base58,
                        "amount": amount.nativeAmount.formatted(),
                        "fee": fee.nativeAmount.formatted(),
                        "amountAfterFees": amountAfterFee.nativeAmount.formatted(),
                        "quarks": "\(amount.onChainAmount.quarks)",
                    ]
                )
                actionButtonState = .normal
                showErrorDialog(error: error)
            }
        }
    }

    func reset() {
        actionButtonState = .normal
        pendingSwapId = nil
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
            title = "Unable to Sell Currency"
            subtitle = "We couldn't complete your sale. Please try again or contact support at support@flipcash.com if the issue persists."
        }

        dialogItem = .error(title: title, subtitle: subtitle) {
            .okay(kind: .destructive) { [weak self] in
                self?.actionButtonState = .normal
            }
        }
    }
}
