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
    
    @StateObject private var viewModel: CurrencySelectionViewModel
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, kind: CurrencySelectionType, ratesController: RatesController) {
        self._viewModel = StateObject(
            wrappedValue: CurrencySelectionViewModel(
                isPresented: isPresented,
                kind: kind,
                ratesController: ratesController
            )
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                ScrollBox(color: .backgroundMain) {
                    List {
                        Group {
                            if viewModel.isSearching {
                                searchingCurrencies()
                            } else {
                                recentCurrencies()
                                otherCurrencies()
                            }
                        }
                        .listRowSeparatorTint(Color.rowSeparator)
                    }
                    .listStyle(.grouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: viewModel.isPresented)
                }
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search Currencies"
            )
        }
        .onAppear {
//            Analytics.open(screen: .currencySelection)
//            ErrorReporting.breadcrumb(.currencyScreen)
        }
    }
    
    @ViewBuilder private func searchingCurrencies() -> some View {
        Section(header: ListHeader("Results")) {
            ForEach(viewModel.searchingCurrencies) { description in
                currencyRow(for: description)
            }
        }
    }
    
    @ViewBuilder private func recentCurrencies() -> some View {
        if !viewModel.availableRecentCurrencies.isEmpty {
            Section(header: ListHeader("Recent Currencies")) {
                ForEach(viewModel.availableRecentCurrencies) { description in
                    currencyRow(for: description, canDelete: true)
                }
            }
        }
    }
    
    @ViewBuilder private func otherCurrencies() -> some View {
        Section(header: ListHeader("Other Currencies")) {
            ForEach(viewModel.availableCurrencies) { description in
                currencyRow(for: description)
            }
        }
    }
    
    @ViewBuilder private func currencyRow(for description: CurrencyDescription, canDelete: Bool = false) -> some View {
        Button {
            viewModel.select(currency: description.currency)
        } label: {
            HStack(spacing: 15) {
                Flag(style: description.currency.flagStyle)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(description.localizedName)
                        .foregroundColor(.textMain)
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
        .buttonStyle(.plain) // Allows default `Button` highlighting
        .if(canDelete) { $0
            .swipeActions {
                Button {
                    withAnimation {
                        viewModel.removeRecent(description.currency)
                    }
                } label: {
                    Image.asset(.delete)
                }
                .tint(.bannerError)
            }
        }
    }
}
