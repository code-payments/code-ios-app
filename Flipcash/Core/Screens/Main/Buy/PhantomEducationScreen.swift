//
//  PhantomEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.phantom-education")

/// "Buy With Phantom" pre-flight: explains the swap, then triggers an async
/// `WalletConnection.connect()` (the wrapper that sets `pendingConnect` so
/// the legacy `isShowingAmountEntry` side-effect on the wallet controller is
/// suppressed). On success, push `phantomConfirm`. User-cancel in Phantom
/// throws `CancellationError` and lands silently back on this screen.
struct PhantomEducationScreen: View {

    let mint: PublicKey
    let amount: ExchangedFiat

    @Environment(AppRouter.self) private var router
    @Environment(WalletConnection.self) private var walletConnection
    @Environment(Session.self) private var session

    @State private var connectTask: Task<Void, Never>?

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 60)
                    PhantomUSDCHero(connected: false)
                    Text("Buy With Phantom")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                    Text("Purchase using Solana USDC in Phantom. Simply connect your wallet and confirm the transaction.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            }
            .safeAreaInset(edge: .bottom) {
                BubbleButton(text: "Connect Your Phantom Wallet") {
                    connect()
                }
                .padding()
            }
        }
        .navigationTitle("Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            connectTask?.cancel()
            connectTask = nil
        }
    }

    private func connect() {
        connectTask?.cancel()
        connectTask = Task {
            // If a prior session already exists, `connect()` returns
            // immediately without deeplinking. Either way, advance.
            do {
                try await walletConnection.connect()
                try Task.checkCancellation()
                router.pushAny(BuyFlowPath.phantomConfirm(mint: mint, amount: amount))
            } catch is CancellationError {
                return
            } catch {
                logger.error("Failed to connect to Phantom", metadata: [
                    "error": "\(error)",
                ])
                // Route through `session.dialogItem` so the alert renders in
                // the dedicated DialogWindow at alert level — a local
                // `.dialog(item:)` is a sheet under the hood and would
                // conflict with the `.buy` nested sheet's presentation queue
                // (tearing this screen down on present).
                session.dialogItem = .init(
                    style: .destructive,
                    title: "Couldn't Connect",
                    subtitle: "We couldn't connect to your Phantom wallet. Please try again.",
                    dismissable: true
                ) { .okay(kind: .destructive) }
            }
        }
    }
}
