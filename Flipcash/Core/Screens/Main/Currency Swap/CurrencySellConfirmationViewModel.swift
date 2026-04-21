//
//  CurrencySellConfirmationViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor @Observable
class CurrencySellConfirmationViewModel {
    @ObservationIgnored let mint: PublicKey
    @ObservationIgnored let amount: ExchangedFiat

    var dialogItem: DialogItem?
    private(set) var actionButtonState: ButtonState = .normal
    var pendingSwapId: SwapId?

    var canDismissSheet: Bool = false

    var fee: ExchangedFiat {
        let bps: UInt64 = 100
        let feeOnChain = TokenAmount(
            quarks: amount.onChainAmount.quarks * bps / 10_000,
            mint: amount.onChainAmount.mint
        )
        let feeScale = Decimal(bps) / Decimal(10_000)
        return ExchangedFiat(
            onChainAmount: feeOnChain,
            nativeAmount: amount.nativeAmount * feeScale,
            currencyRate: amount.currencyRate,
        )
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

    init(mint: PublicKey, amount: ExchangedFiat) {
        self.mint = mint
        self.amount = amount
    }
    
    // MARK: - Actions -

    func performSell(using session: Session) {
        actionButtonState = .loading

        Task {
            do {
                let swapId = try await session.sell(amount: amount, in: mint)
                // Navigate to processing screen
                pendingSwapId = swapId
            } catch {
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to sell currency",
                    metadata: [
                        "mint": mint.base58,
                        "amount": amount.nativeAmount.formatted(),
                        "fee": "\(fee.usdfValue.value)",
                        "amountAfterFees": "\(amountAfterFee.nativeAmount.formatted())",
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

        dialogItem = .init(
            style: .destructive,
            title: title,
            subtitle: subtitle,
            dismissable: true
        ) {
            .okay(kind: .destructive) { [weak self] in
                self?.actionButtonState = .normal
            }
        }
    }
}
