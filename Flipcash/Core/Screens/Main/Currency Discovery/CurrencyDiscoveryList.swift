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
    @Binding var refreshID: Int

    private var mints: [MintMetadata] {
        mintsByCategory[selectedCategory] ?? []
    }

    /// `nil` in the dictionary means "never fetched" → show spinner.
    /// Empty `[]` means "fetched, no results" → show empty state.
    private var isLoading: Bool {
        mintsByCategory[selectedCategory] == nil
    }

    var body: some View {
        List {
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
            } header: {
                Picker("Category", selection: $selectedCategory) {
                    Text("Popular").tag(DiscoverCategory.popular)
                    Text("New").tag(DiscoverCategory.new)
                }
                .pickerStyle(.segmented)
                .frame(height: 44)
                .textCase(nil)
            }
        }
        .overlay {
            if !isLoading, mints.isEmpty {
                VStack(spacing: 10) {
                    Text("No Currencies Yet")
                        .font(.appTextLarge)
                    Text("There are no currencies in this category yet. Check back soon!")
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
        .refreshable {
            refreshID += 1
        }
        .task(id: "\(selectedCategory.rawValue)-\(refreshID)") {
            let category = selectedCategory
            for await batch in container.client.discoverCurrencies(category: category) {
                withAnimation {
                    mintsByCategory[category] = Array(batch.prefix(100))
                }
            }
            // Stream closed without yielding — server has no results
            if mintsByCategory[category] == nil {
                mintsByCategory[category] = []
            }
        }
    }
}
