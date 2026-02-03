//
//  ExternalSwapController.swift
//  Code
//
//  Created by Claude.
//

import SwiftUI
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
    @Published var processing: ExternalSwapProcessing? {
        didSet {
            suppressWalletDialogs = processing != nil
        }
    }

    /// When true, wallet dialogs are suppressed while the processing screen is active.
    @Published private(set) var suppressWalletDialogs: Bool = false

    private let walletConnection: WalletConnection

    /// Creates the controller with the required wallet connection dependency.
    init(walletConnection: WalletConnection) {
        self.walletConnection = walletConnection
    }

    /// Binding to the amount entry presentation state.
    var isShowingAmountEntry: Binding<Bool> {
        Binding(
            get: { self.walletConnection.isShowingAmountEntry },
            set: { self.walletConnection.isShowingAmountEntry = $0 }
        )
    }

    /// Dialog binding that automatically suppresses wallet dialogs during processing.
    var dialogItem: Binding<DialogItem?> {
        Binding(
            get: { self.suppressWalletDialogs ? nil : self.walletConnection.dialogItem },
            set: { self.walletConnection.dialogItem = $0 }
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
