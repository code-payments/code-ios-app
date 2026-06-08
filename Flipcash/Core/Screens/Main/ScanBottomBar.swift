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
                action: onDiscover
            )
            .accessibilityIdentifier("scan-discover-button")

            LargeButton(
                title: "Cash",
                image: .asset(.cash),
                action: onGive
            )
            .accessibilityIdentifier("scan-cash-button")

            LargeButton(
                title: "Send",
                image: Image(.Icons.send),
                action: onSend
            )
            .accessibilityIdentifier("scan-send-button")

            ToastContainer(toast: toast) {
                LargeButton(
                    title: "Wallet",
                    image: .asset(.history),
                    action: onWallet
                )
                .accessibilityIdentifier("scan-wallet-button")
            }
        }
        .padding(.bottom, 10)
    }
}
