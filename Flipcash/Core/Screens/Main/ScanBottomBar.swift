//
//  ScanBottomBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct ScanBottomBar: View {
    let toast: String?
    let onGive: () -> Void
    let onWallet: () -> Void
    let onDiscover: () -> Void
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            LargeButton(
                title: "Discover",
                image: Image(.Icons.coins),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom,
                action: onDiscover
            )
            .accessibilityIdentifier("scan-discover-button")

            LargeButton(
                title: "Cash",
                image: .asset(.cash),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom,
                action: onGive
            )
            .accessibilityIdentifier("scan-cash-button")

            LargeButton(
                title: "Send",
                image: Image(.Icons.send),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom,
                action: onSend
            )
            .accessibilityIdentifier("scan-send-button")

            ToastContainer(toast: toast) {
                LargeButton(
                    title: "Wallet",
                    image: .asset(.history),
                    spacing: 12,
                    maxWidth: 80,
                    maxHeight: 80,
                    fullWidth: true,
                    aligment: .bottom,
                    action: onWallet
                )
                .accessibilityIdentifier("scan-wallet-button")
            }
        }
        .padding(.bottom, 10)
    }
}
