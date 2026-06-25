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
            FakeCashCardsHero()
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

/// Two overlapping decorative cash cards that fill the promo card's hero slot.
/// The back card (`You give`) sits up and to the right; the front card
/// (`You received`) sits down and to the left, each given a slight opposing tilt.
private struct FakeCashCardsHero: View {
    var body: some View {
        ZStack {
            FakeCashCard(caption: "You gave", amount: "$60.00", isFromSelf: true, width: 130)
                .rotationEffect(.degrees(6))
                .offset(x: 46, y: -22)
            FakeCashCard(caption: "You received", amount: "$25.00", isFromSelf: false, width: 130)
                .rotationEffect(.degrees(-7))
                .offset(x: -42, y: 22)
        }
        .accessibilityHidden(true)
    }
}

#Preview("In recents list") {
    NavigationStack {
        List {
            Section("Recents") {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("519 802-3885")
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                        Text("Hi")
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
            SendMoneyPromoCard()
                .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundMain)
        .navigationTitle("Send")
        .toolbarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}

#Preview("Card only") {
    SendMoneyPromoCard()
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
}
