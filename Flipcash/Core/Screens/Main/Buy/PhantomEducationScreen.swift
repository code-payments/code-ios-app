//
//  PhantomEducationScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// "Buy / Launch With Phantom" pre-flight. The connect deeplink fires when
/// the user taps the CTA on this screen — not when Phantom is selected from
/// the picker — so the user sees the education copy before being kicked over
/// to Phantom. On return, `coordinator.state` flips to `.awaitingConfirm` and
/// we push `.phantomConfirm`.
struct PhantomEducationScreen: View {

    let operation: PaymentOperation

    @Environment(AppRouter.self) private var router
    @Environment(PhantomCoordinator.self) private var coordinator
    @Environment(Session.self) private var session

    /// Tracks whether `.phantomConfirm` has been pushed for this view's
    /// lifetime. Necessary because `coordinator.state` re-enters
    /// `.awaitingConfirm` after a sign-cancel (so the user can retry), which
    /// would otherwise stack a second confirm screen via `.onChange`.
    @State private var hasPushedConfirm = false

    private var isConnecting: Bool {
        coordinator.state == .connecting
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                HeroGraphic()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Buy with Phantom using Solana USDC")

                VStack(spacing: 8) {
                    Text("Buy With Phantom")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Purchase using Solana USDC in Phantom. Simply connect your wallet and confirm the transaction.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    coordinator.start(operation)
                } label: {
                    if isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular)
                            Text("Connecting…")
                        }
                    } else {
                        Text("Connect Your Phantom Wallet")
                    }
                }
                .buttonStyle(.filled)
                .disabled(isConnecting)
            }
            .padding(20)
        }
        .navigationTitle("Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: coordinator.state) { _, newState in
            switch newState {
            case .awaitingConfirm where !hasPushedConfirm:
                hasPushedConfirm = true
                router.push(.phantomConfirm(operation))
            case .failed(let reason):
                // Surface the failure as a destructive dialog so the user knows
                // why the connect didn't go through. They can dismiss and tap
                // "Connect Your Phantom Wallet" again to retry.
                session.dialogItem = .init(
                    style: .destructive,
                    title: "Couldn't Connect",
                    subtitle: reason,
                    dismissable: true
                ) { .okay(kind: .destructive) }
            case .awaitingConfirm, .idle, .connecting, .signing:
                break
            }
        }
        .onDisappear {
            // Backing out while the connect deeplink is in flight cancels the
            // coordinator so a stale Phantom return doesn't push confirm onto
            // a stack the user just dismissed.
            if coordinator.state == .connecting {
                coordinator.cancel()
            }
        }
    }
}

private struct HeroGraphic: View {
    var body: some View {
        HStack(spacing: 16) {
            BadgedIcon(icon: Image.asset(.buyPhantom))

            Image(systemName: "plus")
                .foregroundStyle(Color.textMain)
                .font(.system(size: 20, weight: .medium))

            BadgedIcon(
                icon: Image.asset(.buyUSDC),
                badge: Image.asset(.buySolana)
            )
        }
    }
}
