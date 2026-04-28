//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {

    @Environment(AppRouter.self) private var router

    let container: Container
    let sessionContainer: SessionContainer

    @State private var mintsByCategory: [DiscoverCategory: [MintMetadata]] = [:]
    @State private var selectedCategory: DiscoverCategory = .popular

    var body: some View {
        ZStack {
            CurrencyDiscoveryList(
                container: container,
                mintsByCategory: $mintsByCategory,
                selectedCategory: $selectedCategory,
                onSelectMint: { mint in
                    router.push(.currencyInfo(mint), on: .balance)
                }
            )

            if mintsByCategory[selectedCategory] != nil {
                CurrencyInfoFooter {
                    Button("Create Your Own Currency") {
                        router.push(.currencyCreationSummary, on: .balance)
                    }
                    .buttonStyle(.filled)
                }
            }
        }
        .navigationTitle("Currencies")
        .navigationBarTitleDisplayMode(.inline)
    }
}
