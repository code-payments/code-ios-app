//
//  CurrencyDiscoveryList.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

struct CurrencyDiscoveryList: View {
    let container: Container

    @Binding var mints: [MintMetadata]
    @Binding var selectedCategory: DiscoverCategory
    @Binding var selectedMint: PublicKey?
    @Binding var isLoading: Bool
    @Binding var refreshID: Int

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

                    Color.clear
                        .frame(height: 80)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable {
            refreshID += 1
        }
        .task(id: "\(selectedCategory.rawValue)-\(refreshID)") {
            if mints.isEmpty {
                isLoading = true
            }
            for await batch in container.client.discoverCurrencies(category: selectedCategory) {
                withAnimation {
                    mints = Array(batch.prefix(100))
                }
                isLoading = false
            }
            isLoading = false
        }
    }
}
