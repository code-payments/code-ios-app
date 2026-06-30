//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CurrencyCreationPromoCard {
                    router.push(.currencyCreationSummary)
                }

                LeaderboardSectionTitle()

                CurrencyDiscoveryList(
                    onSelectMint: { mint in
                        router.push(.currencyInfo(mint))
                    }
                )
            }
        }
        .background(Color.backgroundMain)
        .navigationTitle("Discover Currencies")
        .toolbarTitleDisplayMode(.inline)
    }
}
