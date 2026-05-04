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

    var body: some View {
        HStack(alignment: .bottom) {
            LargeButton(
                title: "Give",
                image: .asset(.cash),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom,
                action: onGive
            )
            .accessibilityIdentifier("scan-give-button")

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
        }
        .padding(.bottom, 10)
    }
}
