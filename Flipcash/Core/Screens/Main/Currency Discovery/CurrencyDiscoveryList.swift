//
//  CurrencyDiscoveryList.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

struct CurrencyDiscoveryList: View {
    let container: Container

    @Environment(BetaFlags.self) private var betaFlags
    @Binding var mintsByCategory: [DiscoverCategory: [MintMetadata]]
    @Binding var selectedCategory: DiscoverCategory
    @Binding var selectedMint: PublicKey?

    @State private var failedCategories: Set<DiscoverCategory> = []

    private var mints: [MintMetadata] {
        mintsByCategory[selectedCategory] ?? []
    }

    private var isLoading: Bool {
        mintsByCategory[selectedCategory] == nil && !failedCategories.contains(selectedCategory)
    }

    private var isFailed: Bool {
        failedCategories.contains(selectedCategory)
    }

    var body: some View {
        List {
            Section {
                if isLoading {
                    ForEach(1...10, id: \.self) { rank in
                        Button {
                            // Intentionally left blank
                        } label: {
                            CurrencyDiscoverySkeletonRow(rank: rank)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }
                } else {
                    ForEach(mints.indexed(), id: \.element.address) { item in
                        Button {
                            selectedMint = item.element.address
                        } label: {
                            CurrencyDiscoveryRow(rank: item.index + 1, mint: item.element)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }

                    if betaFlags.hasEnabled(.currencyCreation) {
                        Color.clear
                            .frame(height: 80)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listSectionSeparator(.hidden)
        }
        .overlay {
            if isFailed {
                VStack(spacing: 10) {
                    Text("Something Went Wrong")
                        .font(.appTextLarge)
                    Text("We couldn't load currencies right now. Please try again.")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
            } else if !isLoading, mints.isEmpty {
                VStack(spacing: 10) {
                    Text("No New Currencies")
                        .font(.appTextLarge)
                    Text("No currencies have been created in the last week")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .task(id: selectedCategory) {
            let category = selectedCategory
            do {
                for try await batch in container.client.discoverCurrencies(category: category) {
                    failedCategories.remove(category)
                    withAnimation {
                        mintsByCategory[category] = Array(batch.prefix(100))
                    }
                }
                // Stream finished with .ok status — no yield means genuinely empty
                if mintsByCategory[category] == nil {
                    mintsByCategory[category] = []
                }
            } catch {
                if !Task.isCancelled {
                    failedCategories.insert(category)
                }
            }
        }
    }
}
