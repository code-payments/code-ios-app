//
//  CurrencyDiscoveryList.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

struct CurrencyDiscoveryList: View {
    let container: Container

    @Binding var mintsByCategory: [DiscoverCategory: [MintMetadata]]
    @Binding var selectedCategory: DiscoverCategory
    let onSelectMint: (PublicKey) -> Void

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
                            onSelectMint(item.element.address)
                        } label: {
                            CurrencyDiscoveryRow(rank: item.index + 1, mint: item.element)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }

                    Color.clear
                        .frame(height: 80)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listSectionSeparator(.hidden)
        }
        .overlay {
            if isFailed, mints.isEmpty {
                CurrencyDiscoveryErrorState()
            } else if !isLoading, mints.isEmpty {
                CurrencyDiscoveryEmptyState()
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
                if !Task.isCancelled, mintsByCategory[category] == nil {
                    failedCategories.insert(category)
                }
            }
        }
    }
}
