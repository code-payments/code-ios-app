//
//  CurrencyDiscoveryScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

struct CurrencyDiscoveryScreen: View {
    let container: Container
    let sessionContainer: SessionContainer

    @Environment(\.dismiss) private var dismiss
    @Environment(BetaFlags.self) private var betaFlags

    @State private var mintsByCategory: [DiscoverCategory: [MintMetadata]] = [:]
    @State private var selectedCategory: DiscoverCategory = .popular
    @State private var selectedMint: PublicKey?

    var body: some View {
        NavigationStack {
            ZStack {
                CurrencyDiscoveryList(
                    container: container,
                    mintsByCategory: $mintsByCategory,
                    selectedCategory: $selectedCategory,
                    selectedMint: $selectedMint
                )

                if mintsByCategory[selectedCategory] != nil, betaFlags.hasEnabled(.currencyCreation) {
                    CurrencyInfoFooter {
                        Button("Create Your Own Currency") {
                            // No-op for now
                        }
                        .buttonStyle(.filled)
                    }
                }
            }
            .navigationTitle("Currencies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ToolbarCloseButton(action: dismiss.callAsFunction)
                }
            }
            .navigationDestination(item: $selectedMint) { mintAddress in
                if let metadata = mintsByCategory[selectedCategory]?.first(where: { $0.address == mintAddress }) {
                    CurrencyInfoScreen(
                        metadata: metadata,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                } else {
                    CurrencyInfoScreen(
                        mint: mintAddress,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
            }
        }
    }
}
