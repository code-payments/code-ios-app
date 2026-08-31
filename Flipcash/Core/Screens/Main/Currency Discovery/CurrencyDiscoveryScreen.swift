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
                LeaderboardSectionTitle()

                CurrencyDiscoveryList(
                    onSelectMint: { mint in
                        router.push(.currencyInfo(mint))
                    }
                )
            }
        }
        .background(Color.backgroundMain)
        .softScrollEdge(for: .top)
        .navigationTitle("Discover Currencies")
        .toolbarTitleDisplayMode(.inline)
    }
}
