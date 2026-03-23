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

    @State private var mints: [MintMetadata] = []
    @State private var selectedCategory: DiscoverCategory = .popular
    @State private var selectedMint: PublicKey?
    @State private var isLoading: Bool = true
    @State private var refreshID: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                CurrencyDiscoveryList(
                    container: container,
                    mints: $mints,
                    selectedCategory: $selectedCategory,
                    selectedMint: $selectedMint,
                    isLoading: $isLoading,
                    refreshID: $refreshID
                )

                if !isLoading {
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
                if let metadata = mints.first(where: { $0.address == mintAddress }) {
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
