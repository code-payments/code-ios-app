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

    private enum LoadState {
        case loading
        case failed
        case empty
        case loaded([MintMetadata])
    }

    private var loadState: LoadState {
        if let mints {
            mints.isEmpty ? (isFailed ? .failed : .empty) : .loaded(mints)
        } else {
            isFailed ? .failed : .loading
        }
    }

    var body: some View {
        Group {
            switch loadState {
            case .loaded(let mints):
                ForEach(mints.indexed(), id: \.element.address) { item in
                    Button {
                        onSelectMint(item.element.address)
                    } label: {
                        CurrencyDiscoveryRow(rank: item.index + 1, mint: item.element)
                    }
                    .buttonStyle(.plain)
                }
            case .loading:
                ForEach(1...10, id: \.self) { rank in
                    CurrencyDiscoverySkeletonRow(rank: rank)
                }
            case .failed:
                CurrencyDiscoveryStatusView(
                    title: "Something Went Wrong",
                    message: "We couldn't load currencies right now. Please try again."
                )
                .padding(.vertical, 40)
            case .empty:
                CurrencyDiscoveryStatusView(
                    title: "No New Currencies",
                    message: "No currencies have been created in the last week"
                )
                .padding(.vertical, 40)
            }
        }
        .task {
            do {
                for try await batch in container.client.discoverCurrencies(category: .popular) {
                    withAnimation {
                        isFailed = false
                        mints = batch
                    }
                }
                // Stream finished `.ok` without yielding — render the empty state
                // rather than leaving the skeleton visible forever.
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
