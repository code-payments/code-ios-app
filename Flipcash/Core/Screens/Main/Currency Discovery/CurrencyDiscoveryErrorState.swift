//
//  CurrencyDiscoveryErrorState.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

struct CurrencyDiscoveryErrorState: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Something Went Wrong")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text("We couldn't load currencies right now. Please try again.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
}
