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
/// the user taps the CTA — `fundingOperation.confirm()` resumes the
/// continuation that the operation is currently suspended on
/// (`state == .awaitingUserAction(.education(...))`).
struct PhantomEducationScreen: View {

    let fundingOperation: PhantomFundingOperation

    private var isConnecting: Bool {
        if case .awaitingExternal = fundingOperation.state { return true }
        return false
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

                Button(action: fundingOperation.confirm) {
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
        .onDisappear {
            // Backing out while still suspended on the education step or
            // during the handshake cancels the operation so a stale Phantom
            // return doesn't reanimate a flow the user abandoned.
            switch fundingOperation.state {
            case .awaitingUserAction(.education), .awaitingExternal(.phantom):
                fundingOperation.cancel()
            default:
                break
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
