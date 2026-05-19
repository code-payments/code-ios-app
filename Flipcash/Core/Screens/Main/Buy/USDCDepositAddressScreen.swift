//
//  USDCDepositAddressScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Shows the user's authority pubkey as the USDC deposit address. Wallets
/// derive the USDC ATA from this pubkey on send, matching the same ATA the
/// server derives in `StatelessSwap` to observe the balance.
struct USDCDepositAddressScreen: View {

    @Environment(Session.self) private var session
    @State private var buttonState: ButtonState = .normal

    /// Authority pubkey, NOT the derived USDC ATA. Showing the ATA breaks
    /// first-time deposits: it doesn't exist on-chain yet, so wallets fall
    /// back to "treat as owner, derive another ATA" and funds land one
    /// level deeper than the server queries.
    private var depositAddress: String {
        session.owner.authorityPublicKey.base58
    }

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Deposit funds into your wallet by sending USDC to your deposit address below. Tap to copy.")
                    .font(.appTextMedium)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copy(depositAddress)
                } label: {
                    ImmutableField(depositAddress)
                }

                Spacer()

                CodeButton(
                    state: buttonState,
                    style: .filled,
                    title: "Copy Address",
                    action: { copy(depositAddress) }
                )
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
