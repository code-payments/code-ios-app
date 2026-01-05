//
//  CurrencySellConfirmationViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class CurrencySellConfirmationViewModel: ObservableObject {
    let mint: PublicKey
    let amount: ExchangedFiat
        
    @Published var dialogItem: DialogItem?
    @Published private(set) var actionButtonState: ButtonState = .normal
        
    var canDismissSheet: Bool = false
    
    var fee: ExchangedFiat {
        let bps: UInt64 = 100
        let underlying = Quarks(
            quarks: amount.underlying.quarks * bps / 10_000,
            currencyCode: amount.underlying.currencyCode,
            decimals: amount.underlying.decimals
        )
        let converted = Quarks(
            quarks: amount.converted.quarks * bps / 10_000,
            currencyCode: amount.converted.currencyCode,
            decimals: amount.converted.decimals
        )
        
        return ExchangedFiat(
            underlying: underlying,
            converted: converted,
            rate: amount.rate,
            mint: amount.mint
        )
    }
    
    var amountAfterFee: ExchangedFiat {
        do {
            return try amount.subtracting(fee)
        } catch {
            // FIXME: How do we handle subtracting failures?
            return amount
        }
    }
    
    // MARK: - Init -
    
    init(mint: PublicKey, amount: ExchangedFiat) {
        self.mint = mint
        self.amount = amount
    }
    
    // MARK: - Actions -
    
    func performSell(using session: Session, onDismiss: @escaping () -> Void) {
        actionButtonState = .loading
        
        Task {
            do {
                try await session.sell(amount: amount, in: mint)
                showSuccessDialog(onDismiss: onDismiss)
            } catch {
                actionButtonState = .normal
                showErrorDialog(error: error)
            }
        }
    }
    
    // MARK: - Dialogs -
    
    private func showSuccessDialog(onDismiss: @escaping () -> Void) {
        dialogItem = .init(
            style: .success,
            title: "Your Funds Will Be Available Soon",
            subtitle: "They should be available in a few minutes. If you have any issues please contact support@flipcash.com",
            dismissable: false
        ) {
            .okay(kind: .standard) { [weak self] in
                self?.actionButtonState = .success
                onDismiss()
            }
        }
    }
    
    private func showErrorDialog(error: Error) {
        dialogItem = .init(
            style: .destructive,
            title: "Unable to Sell Currency",
            subtitle: "We couldn't complete your sale. Please try again or contact support at support@flipcash.com if the issue persists.",
            dismissable: true
        ) {
            .okay(kind: .destructive) { [weak self] in
                self?.actionButtonState = .normal
            }
        }
    }
}
