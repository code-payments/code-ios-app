//
//  DownloadAppScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct DownloadAppScreen: View {

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 32) {
                Text("Scan to download the\nFlipcash app")
                    .font(.appTextLarge)
                    .foregroundStyle(.textMain)
                    .multilineTextAlignment(.center)

                QRCode(
                    string: URL.downloadApp.absoluteString,
                    showLabel: false,
                    padding: 10,
                    cornerRadius: Metrics.buttonRadius
                )
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)

                HStack(spacing: 28) {
                    Image.asset(.logoApple)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.textMain)
                        .accessibilityHidden(true)

                    Image.asset(.logoAndroid)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.textMain)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .safeAreaInset(edge: .bottom) {
                ShareLink(item: URL.downloadApp) {
                    Text("Share")
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}
