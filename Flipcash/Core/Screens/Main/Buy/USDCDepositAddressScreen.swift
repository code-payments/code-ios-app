//
//  USDCDepositAddressScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Displays the per-user USDC deposit address — the USDF swap PDA itself,
/// matching the address Coinbase Onramp sends to. Anything received here is
/// auto-converted 1:1 to USDF on receipt by the server-side watcher. Mirrors
/// the established settings `DepositScreen` pattern (`ImmutableField` +
/// `CodeButton` with `.successText("Copied")`).
struct USDCDepositAddressScreen: View {

    @Environment(Session.self) private var session
    @State private var buttonState: ButtonState = .normal
    @State private var depositAddress: String?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit funds into your wallet by sending USDC to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let depositAddress {
                    Button {
                        copy(depositAddress)
                    } label: {
                        ImmutableField(depositAddress)
                    }
                } else {
                    Text("Deposit address unavailable")
                        .font(.appTextMedium)
                        .foregroundStyle(.textSecondary)
                }

                Spacer()

                if let depositAddress {
                    CodeButton(
                        state: buttonState,
                        style: .filled,
                        title: "Copy Address",
                        action: { copy(depositAddress) }
                    )
                }
            }
            .padding(20)
        }
        .navigationTitle("Deposit USDC")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // PDA derivation runs Ed25519 isOnCurve checks against up to 256
            // candidate seeds, so resolve once on appear instead of on every
            // body evaluation (`buttonState` flips to `.successText("Copied")`
            // on tap, which would re-derive otherwise). The work is synchronous
            // so `.onAppear` is the right tool — `.task` would be misleading.
            depositAddress = MintMetadata.usdf
                .timelockSwapAccounts(owner: session.owner.authorityPublicKey)?
                .pda.publicKey.base58
        }
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        buttonState = .successText("Copied")
    }
}
