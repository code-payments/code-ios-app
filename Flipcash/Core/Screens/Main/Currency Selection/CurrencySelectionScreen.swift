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
                            if !viewModel.searchingCurrencies.isEmpty {
                                ListSectionTitle("Results")
                                ForEach(viewModel.searchingCurrencies) { description in
                                    CurrencyRow(
                                        description: description,
                                        viewModel: viewModel,
                                        allowDelete: false,
                                        isLast: description.id == viewModel.searchingCurrencies.last?.id
                                    )
                                }
                            }
                        } else {
                            if !viewModel.availableRecentCurrencies.isEmpty {
                                ListSectionTitle("Recent Regions")
                                ForEach(viewModel.availableRecentCurrencies) { description in
                                    CurrencyRow(
                                        description: description,
                                        viewModel: viewModel,
                                        allowDelete: !viewModel.isCurrencyActive(description.currency),
                                        isLast: description.id == viewModel.availableRecentCurrencies.last?.id
                                    )
                                }
                            }
                            ListSectionTitle("Other Regions")
                            ForEach(viewModel.availableCurrencies) { description in
                                CurrencyRow(
                                    description: description,
                                    viewModel: viewModel,
                                    allowDelete: false,
                                    isLast: description.id == viewModel.availableCurrencies.last?.id
                                )
                            }
                        }
                    }
                    // Rows v2: each row draws its own divider and section titles are rows, so the
                    // list adds no insets, separators or header chrome of its own.
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.backgroundMain)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 0)
                .scrollContentBackground(.hidden)
                .overlay {
                    if viewModel.isSearching && viewModel.searchingCurrencies.isEmpty {
                        SearchResultsUnavailableView(searchText: viewModel.searchText)
                    }
                }
            }
            .navigationTitle("Select Region")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
            .searchable(
                text: $viewModel.searchText,
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
    let isLast: Bool

    var body: some View {
        if allowDelete {
            CurrencyRowContent(description: description, viewModel: viewModel, isLast: isLast)
                .swipeActions {
                    Button {
                        withAnimation { viewModel.removeRecent(description.currency) }
                    } label: {
                        Image.icon(.trashCan)
                    }
                    .tint(.bannerError)
                    .accessibilityLabel("Remove")
                }
        } else {
            CurrencyRowContent(description: description, viewModel: viewModel, isLast: isLast)
        }
    }
}

private struct CurrencyRowContent: View {
    @Environment(\.dismiss) private var dismiss
    let description: CurrencyDescription
    let viewModel: CurrencySelectionViewModel
    let isLast: Bool

    var body: some View {
        ListRow(description.localizedName, showsDivider: !isLast) {
            viewModel.select(currency: description.currency)
            dismiss()
        } leading: {
            Flag(style: description.currency.flagStyle, size: .none)
                .frame(width: ListRowMetrics.flagSize, height: ListRowMetrics.flagSize)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color.rowSeparator, lineWidth: 1) }
        } trailing: {
            if viewModel.isCurrencyActive(description.currency) {
                Image.icon(.checkmark1)
                    .iconSize(22)
                    .foregroundStyle(Color.textMain)
            }
        }
        .font(.appTextMedium)
        .accessibilityAddTraits(viewModel.isCurrencyActive(description.currency) ? .isSelected : [])
        .disabled(viewModel.isSelectionDisabled(for: description.currency))
    }
}
