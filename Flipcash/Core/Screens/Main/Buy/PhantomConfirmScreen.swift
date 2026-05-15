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
/// `fundingOperation.confirm()`, which resumes the operation's suspended
/// continuation and triggers the sign request deeplink to Phantom.
struct PhantomConfirmScreen: View {

    let fundingOperation: PhantomFundingOperation

    /// True while the operation is doing chain work (sign request sent,
    /// awaiting deeplink return, or running the simulate + submit step).
    private var isSigning: Bool {
        switch fundingOperation.state {
        case .awaitingExternal(.phantom), .working:
            return true
        default:
            return false
        }
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

                Button(action: fundingOperation.confirm) {
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
            // Backing out before Phantom returns cancels the operation so a
            // stale deeplink callback doesn't complete a flow the user
            // abandoned.
            switch fundingOperation.state {
            case .awaitingUserAction(.confirm), .awaitingExternal(.phantom):
                fundingOperation.cancel()
            default:
                break
            }
        }
    }
}
