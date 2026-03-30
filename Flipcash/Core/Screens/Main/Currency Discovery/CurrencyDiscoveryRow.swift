//
//  CurrencyDiscoveryRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryRow: View {
    let rank: Int
    let mint: MintMetadata

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .monospacedDigit()
                .frame(width: 24, alignment: .center)

            RemoteImage(url: mint.imageURL)
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)

                if let marketCap = mint.launchpadMetadata?.marketCap, marketCap > 0 {
                    Text(marketCap, format: .compactCurrency(code: .usd))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .contentTransition(.numericText())
                }
            }

            Spacer()

            if let metrics = mint.holderMetrics {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(metrics.currentHolders, format: .number.notation(.compactName)) Holders")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                        .contentTransition(.numericText())

                    if let weeklyDelta = metrics.holderDeltas.first(where: { $0.range == .lastWeek }) {
                        Text(Self.formatDelta(weeklyDelta.delta))
                            .font(.appTextSmall)
                            .foregroundStyle(.green)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Formatting -

private extension CurrencyDiscoveryRow {
    static func formatDelta(_ delta: Int64) -> String {
        let sign = delta >= 0 ? "+" : ""
        let compact = delta.formatted(.number.notation(.compactName))
        return "\(sign)\(compact) this week"
    }
}
