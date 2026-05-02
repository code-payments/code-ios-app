//
//  CurrencyDiscoverySkeletonRow.swift
//  Flipcash
//

import SwiftUI

struct CurrencyDiscoverySkeletonRow: View {
    let rank: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .monospacedDigit()
                .frame(width: 32, alignment: .center)
                .unredacted()

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Currency Name")
                    .font(.appTextMedium)

                Text("$1.2K")
                    .font(.appTextSmall)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("92 Holders")
                    .font(.appTextSmall)

                Text("+8 this week")
                    .font(.appTextSmall)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .redacted(reason: .placeholder)
    }
}
