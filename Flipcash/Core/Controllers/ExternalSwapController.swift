//
//  ExternalSwapController.swift
//  Code
//
//  Created by Claude.
//

import SwiftUI
import Combine
import FlipcashCore
import FlipcashUI

/// Coordinates the external wallet swap flow (Phantom) and its UI state.
///
/// Responsibilities:
/// - Presenting amount entry via `walletConnection.isShowingAmountEntry`
/// - Initiating the external swap request
/// - Navigating to the processing screen with the correct swap payload
/// - Suppressing wallet dialogs while the processing screen is active
@MainActor
final class ExternalSwapController: ObservableObject {
    /// Current processing context. When set, the processing screen should be shown.
    @Published var processing: ExternalSwapProcessing?

    private let walletConnection: WalletConnection
    private var dialogObserver: AnyCancellable?

    /// Creates the controller with the required wallet connection dependency.
    init(walletConnection: WalletConnection) {
        self.walletConnection = walletConnection

        // `WalletConnection` is a separate `ObservableObject` whose `dialogItem` changes
        // aren't visible to views observing *this* controller. We forward its change
        // notifications so SwiftUI knows to re-evaluate our `dialogItem` binding.
        dialogObserver = walletConnection.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        walletConnection.onCancelled = { [weak self] in
            guard let self else { return }

            // Clear processing first to pop the SwapProcessingScreen. The dialog must
            // be deferred because SwiftUI can't present a sheet while a navigation
            // transition is animating — setting both in the same run-loop tick causes
            // the sheet to be silently dropped.
            self.processing = nil

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.walletConnection.dialogItem = .init(
                    style: .destructive,
                    title: "Transaction Cancelled",
                    subtitle: "The transaction was cancelled in your wallet",
                    dismissable: true
                ) {
                    .okay(kind: .destructive)
                }
            }
        }
    }

    /// The dialog to present from `CurrencyInfoScreen`.
    ///
    /// This is a computed `Binding` over `walletConnection.dialogItem`. Dialogs originate from
    /// two places — `WalletConnection` (success/error after signing) and `onCancelled`
    /// (user cancelled in External Wallet). Both set `walletConnection.dialogItem` and this
    /// binding surfaces it so `CurrencyInfoScreen` only needs
    /// `.dialog(item: externalSwapController.dialogItem)`.
    ///
    /// **Why this works:** `WalletConnection` is a separate `ObservableObject` whose changes
    /// aren't visible to views that observe this controller. The `dialogObserver` in `init`
    /// forwards `WalletConnection.objectWillChange` → `self.objectWillChange` so SwiftUI
    /// re-evaluates this binding whenever the underlying value changes — both for presentation
    /// *and* dismissal.
    ///
    /// **Suppression during processing:** While `processing != nil` the getter returns `nil`
    /// to prevent wallet dialogs from appearing over the `SwapProcessingScreen`.
    var dialogItem: Binding<DialogItem?> {
        Binding(
            get: { self.processing != nil ? nil : self.walletConnection.dialogItem },
            set: { self.walletConnection.dialogItem = $0 }
        )
    }

    /// Binding to the amount entry presentation state.
    var isShowingAmountEntry: Binding<Bool> {
        Binding(
            get: { self.walletConnection.isShowingAmountEntry },
            set: { self.walletConnection.isShowingAmountEntry = $0 }
        )
    }

    /// Starts the Phantom connection flow.
    func connectToPhantom() {
        walletConnection.connectToPhantom()
    }

    /// Requests an external swap and prepares the processing context.
    ///
    /// - Parameters:
    ///   - usdc: Amount of USDC to swap (in quarks)
    ///   - mint: Destination mint public key
    ///   - token: Destination mint metadata
    func requestSwap(usdc: Quarks, mint: PublicKey, token: MintMetadata) async throws {
        let result = try await walletConnection.requestUsdcToUsdfSwap(usdc: usdc, token: token)
        processing = ExternalSwapProcessing(
            swapId: result.swapId,
            mint: mint,
            amount: result.amount
        )
        walletConnection.isShowingAmountEntry = false
    }

    /// Dismisses the processing screen and clears any pending wallet dialogs.
    func dismissProcessing() {
        walletConnection.dialogItem = nil
        processing = nil
    }
}

/// Data required to render the processing screen for an external wallet swap.
struct ExternalSwapProcessing: Identifiable, Hashable {
    let swapId: SwapId
    let mint: PublicKey
    let amount: ExchangedFiat

    var id: String { swapId.publicKey.base58 }
}
