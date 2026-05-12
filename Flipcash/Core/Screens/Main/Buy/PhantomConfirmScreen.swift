//
//  PhantomConfirmScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.phantom-confirm")

/// Post-Phantom-auth confirmation screen. The user taps "Confirm In Phantom" to
/// trigger `WalletConnection.requestSwap(...)`, which deep-links into Phantom
/// for transaction signing. When `walletConnection.state` transitions to
/// `.buying(ExternalSwapProcessing, isFailed: false)`, the `.onChange`
/// observer pushes `BuyFlowPath.processing` onto the buy stack with the swap
/// id and Phantom swap type. From there `SwapProcessingScreen` owns the
/// remaining lifecycle (success / cancel display) via its own
/// `walletConnection.isProcessingCancelled` observer.
struct PhantomConfirmScreen: View {

    let mint: PublicKey
    let amount: ExchangedFiat

    @Environment(AppRouter.self) private var router
    @Environment(WalletConnection.self) private var walletConnection
    @Environment(Session.self) private var session

    @State private var dialogItem: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 60)
                    PhantomUSDCHero(connected: true)
                    Text("Connected")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                    Text("Confirm the transaction in Phantom to continue")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            }
            .safeAreaInset(edge: .bottom) {
                BubbleButton(text: "Confirm In Phantom") {
                    confirmInPhantom()
                }
                .padding()
            }
        }
        .navigationTitle("Confirmation")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialogItem)
        .onChange(of: walletConnection.state) { _, newState in
            // Push the processing screen the moment the swap context appears.
            // `state` flips to `.buying(..., isFailed: false)` immediately
            // after Phantom returns a signed transaction (see
            // `WalletConnection.completeSwap`). A later chain-submission
            // failure flips `isFailed` to true; `SwapProcessingScreen`
            // observes that via `walletConnection.isProcessingCancelled`.
            guard case .buying(let processing, false) = newState else { return }
            router.pushAny(BuyFlowPath.processing(
                swapId: processing.swapId,
                currencyName: processing.currencyName,
                amount: amount,
                swapType: .buyWithPhantom
            ))
        }
    }

    private func confirmInPhantom() {
        Task {
            do {
                let metadata = try await session.fetchMintMetadata(mint: mint)
                try await walletConnection.requestSwap(
                    usdc: amount.onChainAmount,
                    token: metadata.metadata
                )
            } catch {
                logger.error("Failed to request Phantom swap", metadata: [
                    "mint": "\(mint.base58)",
                    "amount": "\(amount.nativeAmount.formatted())",
                    "error": "\(error)",
                ])
                ErrorReporting.captureError(
                    error,
                    reason: "Failed to request Phantom swap from PhantomConfirmScreen",
                    metadata: ["mint": mint.base58]
                )
                dialogItem = .init(
                    style: .destructive,
                    title: "Something Went Wrong",
                    subtitle: "We couldn't open Phantom. Please try again.",
                    dismissable: true
                ) { .okay(kind: .destructive) }
            }
        }
    }
}
