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
                VStack(spacing: 0) {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Popular").tag(DiscoverCategory.popular)
                        Text("New").tag(DiscoverCategory.new)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    list()
                }

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

    @ViewBuilder
    private func list() -> some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(mints.enumerated()), id: \.element.address) { index, mint in
                    Button {
                        selectedMint = mint.address
                    } label: {
                        CurrencyDiscoveryRow(rank: index + 1, mint: mint)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
