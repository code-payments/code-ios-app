//
//  CurrencyDiscoveryStatusView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDiscoveryStatusView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text(message)
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}
