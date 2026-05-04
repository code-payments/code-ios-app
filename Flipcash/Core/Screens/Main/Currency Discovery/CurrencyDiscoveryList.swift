//
//  CurrencyDiscoveryList.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

struct CurrencyDiscoveryList: View {
    let container: Container
    let onSelectMint: (PublicKey) -> Void

    @State private var mints: [MintMetadata]?
    @State private var isFailed: Bool = false

    private var isLoading: Bool { mints == nil && !isFailed }

    var body: some View {
        Group {
            if let mints, !mints.isEmpty {
                ForEach(mints.indexed(), id: \.element.address) { item in
                    Button {
                        onSelectMint(item.element.address)
                    } label: {
                        CurrencyDiscoveryRow(rank: item.index + 1, mint: item.element)
                    }
                    .buttonStyle(.plain)
                }
            } else if isLoading {
                ForEach(1...10, id: \.self) { rank in
                    CurrencyDiscoverySkeletonRow(rank: rank)
                }
            } else if isFailed {
                CurrencyDiscoveryErrorState()
                    .padding(.vertical, 40)
            } else {
                CurrencyDiscoveryEmptyState()
                    .padding(.vertical, 40)
            }
        }
        .task {
            do {
                for try await batch in container.client.discoverCurrencies(category: .popular) {
                    isFailed = false
                    withAnimation {
                        mints = batch
                    }
                }
                if mints == nil {
                    mints = []
                }
            } catch {
                if !Task.isCancelled, mints == nil {
                    isFailed = true
                }
            }
        }
    }
}
