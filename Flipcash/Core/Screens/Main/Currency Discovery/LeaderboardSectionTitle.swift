//
//  LeaderboardSectionTitle.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct LeaderboardSectionTitle: View {

    @Environment(Session.self) private var session

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Leaderboard")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            if let threshold = session.userFlags?.minimumHolderValue {
                Button {
                    showRankingInfo(threshold: threshold)
                } label: {
                    Image.system(.info)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func showRankingInfo(threshold: TokenAmount) {
        let amount = ExchangedFiat.compute(
            onChainAmount: threshold,
            rate: .oneToOne,
            supplyQuarks: 0
        )
        session.dialogItem = .info(
            title: "Leaderboard Ranking",
            subtitle: "People must have a minimum balance of \(amount.nativeAmount.formatted(minimumFractionDigits: 0)) USD to be counted"
        )
    }
}
