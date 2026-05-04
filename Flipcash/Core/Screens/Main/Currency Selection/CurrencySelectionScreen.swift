//
//  CurrencySelectionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-09.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencySelectionScreen: View {

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CurrencySelectionViewModel

    // MARK: - Init -

    init(ratesController: RatesController) {
        self._viewModel = State(initialValue: CurrencySelectionViewModel(ratesController: ratesController))
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                List {
                    Group {
                        if viewModel.isSearching {
                            Section(header: ListHeader("Results")) {
                                ForEach(viewModel.searchingCurrencies) { description in
                                    CurrencyRow(description: description, viewModel: viewModel, allowDelete: false, dismiss: dismiss)
                                }
                            }
                        } else {
                            if !viewModel.availableRecentCurrencies.isEmpty {
                                Section(header: ListHeader("Recent Regions")) {
                                    ForEach(viewModel.availableRecentCurrencies) { description in
                                        CurrencyRow(description: description, viewModel: viewModel, allowDelete: true, dismiss: dismiss)
                                    }
                                }
                            }
                            Section(header: ListHeader("Other Regions")) {
                                ForEach(viewModel.availableCurrencies) { description in
                                    CurrencyRow(description: description, viewModel: viewModel, allowDelete: false, dismiss: dismiss)
                                }
                            }
                        }
                    }
                    .listRowSeparatorTint(Color.rowSeparator)
                }
                .listStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Select Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton { dismiss() }
                }
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Regions"
            )
            .foregroundStyle(Color.textMain)
        }
    }
}

private struct CurrencyRow: View {
    let description: CurrencyDescription
    let viewModel: CurrencySelectionViewModel
    let allowDelete: Bool
    let dismiss: DismissAction

    var body: some View {
        Button {
            viewModel.select(currency: description.currency)
            dismiss()
        } label: {
            HStack(spacing: 15) {
                Flag(style: description.currency.flagStyle)
                VStack(alignment: .leading, spacing: 5) {
                    Text(description.localizedName)
                        .foregroundStyle(.textMain)
                        .font(.appTextMedium)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(10)
                }
                Spacer()
                CheckView(active: viewModel.isCurrencyActive(description.currency))
            }
            .padding(.vertical, 12)
            .background(Color.backgroundMain)
        }
        .opacity(viewModel.opacity(for: description.currency))
        .disabled(viewModel.isSelectionDisabled(for: description.currency))
        .listRowBackground(Color.backgroundMain)
        .buttonStyle(.plain)
        .swipeActions {
            if allowDelete {
                Button {
                    withAnimation { viewModel.removeRecent(description.currency) }
                } label: {
                    Image.asset(.delete)
                }
                .tint(.bannerError)
            }
        }
    }
}
