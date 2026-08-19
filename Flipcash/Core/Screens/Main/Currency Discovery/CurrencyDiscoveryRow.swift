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
    /// Drives which metric is prominent (trailing value + delta) and which is the
    /// secondary line under the name. Callers pass `.marketCap` under v2; the
    /// default stays on holders for the legacy UI. See ``RankingSystem``.
    var rankingSystem: RankingSystem = .holders

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 32, alignment: .center)

            RemoteImage(url: mint.imageURL)
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(mint.name)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)

                secondaryLine
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                primaryValue
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .contentTransition(.numericText())

                deltaLine
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// The secondary metric shown under the name: the one the list is *not* ranked by.
    @ViewBuilder private var secondaryLine: some View {
        switch rankingSystem {
        case .holders:
            marketCapText
        case .marketCap:
            holdersText
        }
    }

    /// The prominent, ranked metric shown trailing.
    @ViewBuilder private var primaryValue: some View {
        switch rankingSystem {
        case .holders:
            holdersText
        case .marketCap:
            marketCapText
        }
    }

    /// The weekly change in the ranked metric.
    @ViewBuilder private var deltaLine: some View {
        switch rankingSystem {
        case .holders:
            if let metrics = mint.holderMetrics,
               let weekly = metrics.holderDeltas.first(where: { $0.range == .lastWeek }) {
                Text(Self.formatHolderDelta(weekly.delta))
                    .font(.appTextSmall)
                    .foregroundStyle(weekly.delta > 0 ? Color.Sentiment.positive : Color.Sentiment.neutral)
                    .contentTransition(.numericText())
            }
        case .marketCap:
            if let metrics = mint.marketCapMetrics,
               let weekly = metrics.marketCapDeltas.first(where: { $0.range == .lastWeek }) {
                Text(Self.formatMarketCapDelta(weekly.delta))
                    .font(.appTextSmall)
                    .foregroundStyle(weekly.delta > 0 ? Color.Sentiment.positive : Color.Sentiment.neutral)
                    .contentTransition(.numericText())
            }
        }
    }

    @ViewBuilder private var holdersText: some View {
        if let metrics = mint.holderMetrics {
            Text("\(metrics.currentHolders, format: .number.notation(.compactName)) \(metrics.currentHolders == 1 ? "person" : "people")")
        }
    }

    @ViewBuilder private var marketCapText: some View {
        if let marketCap = marketCapValue, marketCap > 0 {
            Text(marketCap, format: .compactCurrency(code: .usd))
        }
    }

    /// Prefer the Discover market-cap metric; fall back to the bonding-curve
    /// estimate on `launchpadMetadata` when the metric isn't populated.
    private var marketCapValue: Double? {
        if let current = mint.marketCapMetrics?.currentMarketCap, current > 0 {
            return current
        }
        return mint.launchpadMetadata?.marketCap
    }
}

// MARK: - Formatting -

private extension CurrencyDiscoveryRow {
    static func formatHolderDelta(_ delta: Int64) -> String {
        let sign = delta >= 0 ? "+" : ""
        let compact = delta.formatted(.number.notation(.compactName))
        return "\(sign)\(compact) this week"
    }

    static func formatMarketCapDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        let compact = delta.formatted(.compactCurrency(code: .usd))
        return "\(sign)\(compact) this week"
    }
}
