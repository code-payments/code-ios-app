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
    @State private var creationState = CurrencyCreationState()

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
                        NavigationLink("Create Your Own Currency", value: CurrencyCreationStep.summary)
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
            .navigationDestination(for: CurrencyCreationStep.self) { step in
                switch step {
                case .summary:
                    CurrencyCreationSummaryScreen()
                case .wizard:
                    CurrencyCreationWizardScreen(
                        state: creationState,
                        sessionContainer: sessionContainer
                    )
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
