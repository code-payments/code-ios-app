//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {

    @Environment(AppRouter.self) private var router

    /// The new tab-bar UI surfaces currency creation as a Wallet tile, so Discover
    /// drops its promo entirely; the legacy UI keeps it as the first row above the
    /// leaderboard.
    private var hidesPromo: Bool { BetaFlags.shared.hasEnabled(.newUI) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !hidesPromo {
                    promoCard
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

    private var promoCard: some View {
        CurrencyCreationPromoCard {
            router.push(.currencyCreationSummary)
        }
    }
}
