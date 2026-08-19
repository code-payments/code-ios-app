//
//  ConfirmationRows.swift
//  Flipcash
//
//  Shared building blocks for the swap-style receipt card used by the Get
//  (buy) and Convert confirmation screens: a centered "You X" amount block with
//  the currency's coin, and a leading-title / trailing-value breakdown line.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A centered label-over-amount block with the currency's icon, used for the
/// "You Pay" / "You Receive" / "You Get" / "You Convert" rows on a receipt.
struct ConfirmationAmountRow: View {
    let title: String
    let currencyName: String
    let imageURL: URL?
    let amount: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                if let imageURL {
                    RemoteImage(url: imageURL)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
                Text(amount)
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
                    .contentTransition(.numericText())
            }
        }
        // The icon is the only visual carrier of WHICH currency this is —
        // VoiceOver needs the name spoken alongside the amount.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(amount) of \(currencyName)")
    }
}

/// A leading title / trailing value line for a receipt's fee breakdown.
struct ConfirmationBreakdownRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .contentTransition(.numericText())
        }
    }
}
