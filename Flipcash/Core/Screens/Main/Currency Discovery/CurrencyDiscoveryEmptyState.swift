//
//  CurrencyDiscoveryEmptyState.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDiscoveryEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("No New Currencies")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text("No currencies have been created in the last week")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}
