//
//  ScanBottomBar.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct ScanBottomBar: View {
    let toast: String?
    let showSend: Bool
    let sendBadgeCount: Int
    let showTips: Bool
    let tipsBadgeCount: Int
    let onGive: () -> Void
    let onWallet: () -> Void
    let onDiscover: () -> Void
    let onSend: () -> Void
    let onTips: () -> Void

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

            if showSend {
                LargeButton(
                    title: "Send",
                    image: Image(.Icons.send),
                    badgeCount: sendBadgeCount,
                    action: onSend
                )
                .accessibilityIdentifier("scan-send-button")
            }

            if showTips {
                LargeButton(
                    title: "Tips",
                    image: Image(.Icons.tips),
                    badgeCount: tipsBadgeCount,
                    action: onTips
                )
                .accessibilityIdentifier("scan-tips-button")
            }

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
