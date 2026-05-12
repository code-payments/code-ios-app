//
//  USDCDepositAddressScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Displays the per-user USDC deposit address — the USDF swap PDA's USDC ATA.
/// Anything received here is auto-converted 1:1 to USDF on receipt by the
/// server-side watcher. Mirrors the established settings `DepositScreen`
/// pattern (`ImmutableField` + `CodeButton` with `.successText("Copied")`).
struct USDCDepositAddressScreen: View {

    let mint: PublicKey
    let amount: ExchangedFiat

    @Environment(Session.self) private var session
    @State private var buttonState: ButtonState = .normal

    private var depositAddress: String? {
        // The per-user staging address on USDF: USDC sent here is converted
        // 1:1 to USDF for the user. `ata` is the SPL-token receive address
        // derived from the swap PDA (an SPL transfer must target a token
        // account, not the PDA itself).
        MintMetadata.usdf
            .timelockSwapAccounts(owner: session.owner.authorityPublicKey)?
            .ata.publicKey.base58
    }

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
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        buttonState = .successText("Copied")
    }
}
