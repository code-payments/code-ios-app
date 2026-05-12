//
//  PhantomEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// "Buy With Phantom" pre-flight: explains the swap, then triggers
/// `WalletConnection.connectToPhantom()`. When Phantom returns and the
/// underlying `session` becomes non-nil, the `.onChange` observer pushes
/// `BuyFlowPath.phantomConfirm` automatically. `initial: true` also handles
/// the case where the user lands on this screen already connected (a prior
/// Phantom session persists in the keychain across launches).
struct PhantomEducationScreen: View {

    let mint: PublicKey
    let amount: ExchangedFiat

    @Environment(AppRouter.self) private var router
    @Environment(WalletConnection.self) private var walletConnection

    /// Single-shot advance latch. Without this, popping back from
    /// `phantomConfirm` re-fires the auto-push (the user is still connected)
    /// and the back button effectively does nothing.
    @State private var didAutoAdvance = false

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
                    walletConnection.connectToPhantom()
                }
                .padding()
            }
        }
        .navigationTitle("Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: walletConnection.session != nil, initial: true) { _, isConnected in
            // Auto-advance when Phantom returns from the connect deeplink, or
            // immediately on appear if a prior session already exists.
            guard isConnected, !didAutoAdvance else { return }
            didAutoAdvance = true
            router.pushAny(BuyFlowPath.phantomConfirm(mint: mint, amount: amount))
        }
    }
}
