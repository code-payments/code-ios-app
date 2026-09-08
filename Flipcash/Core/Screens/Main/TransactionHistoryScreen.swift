//
//  TransactionHistoryScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-31.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// One token's activity, newest first. Tapping a row opens
/// ``TransactionDetailsScreen``, which is also where a pending cash link is
/// cancelled.
struct TransactionHistoryScreen: View {

    @Environment(HistoryController.self) private var historyController

    private let mint: PublicKey

    // MARK: - Init -

    init(mint: PublicKey) {
        self.mint = mint
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            List {
                Section {
                    switch historyController.loadingState {
                    case .loaded(let activities):
                        ForEach(activities) { activity in
                            ActivityRow(activity: activity)
                                .padding(.horizontal, 20)
                                .listRowBackground(Color.clear)
                        }
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(.rowSeparator)
                .listSectionSeparator(.hidden, edges: .top)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Activity")
        }
        .task(id: mint) {
            await historyController.setActiveMint(mint)
        }
    }
}
