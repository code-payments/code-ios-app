//
//  PhantomConfirmScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Post-handshake confirmation. Tapping Confirm calls
/// `PhantomCoordinator.confirm()`, which dispatches the right
/// `WalletConnection.request*` for the carried operation kind.
///
/// The completion routing (push processing for buy, fullScreenCover for
/// launch) is observed by the picker's caller — `BuyAmountScreen` watches
/// `coordinator.processing`, the wizard watches `coordinator.launchProcessing`.
/// This screen just kicks off the sign request.
struct PhantomConfirmScreen: View {

    let operation: PaymentOperation

    @Environment(PhantomCoordinator.self) private var coordinator

    private var isSigning: Bool {
        coordinator.state == .signing
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 24) {
                Spacer()

                BadgedIcon(
                    icon: Image.asset(.buyPhantom),
                    badge: Image.asset(.buyCheckmark)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Phantom connected")

                VStack(spacing: 8) {
                    Text("Connected")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)

                    Text("Confirm the transaction in Phantom to continue")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button(action: coordinator.confirm) {
                    if isSigning {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(.circular)
                            Text("Waiting for Phantom…")
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text("Confirm in your")
                            Image.asset(.phantom)
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text("Phantom")
                        }
                    }
                }
                .buttonStyle(.filled)
                .disabled(isSigning)
            }
            .padding(20)
        }
        .navigationTitle("Confirmation")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Backing out before Phantom returns cancels the pending swap so
            // a future unrelated deeplink doesn't complete a stale operation.
            coordinator.cancel()
        }
    }
}
