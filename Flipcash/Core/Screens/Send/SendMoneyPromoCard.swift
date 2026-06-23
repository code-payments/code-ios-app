//
//  SendMoneyPromoCard.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// CTA shown in the Send picker when contact access is denied. Existing
/// conversations still list above it; this nudges the user to grant access so
/// they can reach the rest of their friends. Routes to Settings.
struct SendMoneyPromoCard: View {

    var body: some View {
        VStack(spacing: 20) {
            // Illustration slot — the cash-cards hero art drops in here.
            Color.clear
                .frame(height: 140)

            Text("Send Money to Your Friends")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
                .multilineTextAlignment(.center)

            Button("Allow Contact Access in Settings") {
                URL.openSettings()
            }
            .buttonStyle(.filledCompact)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rowSeparator, lineWidth: 1)
        }
    }
}

#Preview {
    SendMoneyPromoCard()
        .padding()
        .background(Color.backgroundMain)
}
