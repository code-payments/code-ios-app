//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CurrencyDiscoveryList(
                    onSelectMint: { mint in
                        Analytics.tokenInfoOpened(from: .openedFromDiscovery, mint: mint)
                        router.push(.currencyInfo(mint))
                    }
                )
            }
        }
        .background(Color.backgroundMain)
        .navigationTitle("Currency Leaderboard")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if let threshold = session.userFlags?.minimumHolderValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showRankingInfo(threshold: threshold)
                    } label: {
                        Image.system(.info)
                    }
                    .accessibilityLabel("Leaderboard Ranking")
                }
            }
        }
    }

    private func showRankingInfo(threshold: TokenAmount) {
        let amount = ExchangedFiat.compute(
            onChainAmount: threshold,
            rate: .oneToOne,
            supplyQuarks: 0
        )
        session.dialogItem = .info(
            title: "Leaderboard Ranking",
            subtitle: "Members must have a minimum balance of \(amount.nativeAmount.formatted(minimumFractionDigits: 0)) USD to be counted"
        )
    }
}
