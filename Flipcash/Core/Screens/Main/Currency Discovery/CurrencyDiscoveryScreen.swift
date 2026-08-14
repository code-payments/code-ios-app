//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {

    @Environment(AppRouter.self) private var router

    /// The new tab-bar UI floats the creation promo at the bottom; the legacy UI
    /// keeps it as the first row above the leaderboard.
    private var floatsPromo: Bool { BetaFlags.shared.hasEnabled(.newUI) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !floatsPromo {
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
        .safeAreaInset(edge: .bottom) {
            if floatsPromo {
                // Floats over the list as Liquid Glass; the rows blur through behind it.
                CurrencyCreationPromoCard(surface: .glass) {
                    router.push(.currencyCreationSummary)
                }
                .padding(.bottom, 8)
            }
        }
        .navigationTitle("Discover Currencies")
        .toolbarTitleDisplayMode(.inline)
    }

    private var promoCard: some View {
        CurrencyCreationPromoCard {
            router.push(.currencyCreationSummary)
        }
    }
}
