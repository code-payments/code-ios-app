//
//  CurrencySelectionScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-09.
//

import SwiftUI
import CodeUI
import CodeServices

struct CurrencySelectionScreen: View {
    
    @StateObject private var viewModel: CurrencySelectionViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> CurrencySelectionViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                ModalHeaderBar(title: Localized.Title.selectCurrency, isPresented: viewModel.isPresented)
                
                SearchBar(content: $viewModel.searchText, isActive: $viewModel.isFocused) { searchBar in
                    searchBar.placeholder = Localized.Subtitle.searchCurrencies
                }
                .padding([.leading, .trailing], 10)
                
                ScrollBox(color: .backgroundMain) {
                    List {
                        if viewModel.isSearching {
                            searchingCurrencies()
                        } else {
                            recentCurrencies()
                            otherCurrencies()
                        }
                    }
                    .listStyle(.grouped)
                    .backportScrollContentBackground(.hidden)
                    .background(Color.backgroundMain)
                }
            }
        }
        .onAppear {
            Analytics.open(screen: .currencySelection)
            ErrorReporting.breadcrumb(.currencyScreen)
        }
    }
    
    @ViewBuilder private func searchingCurrencies() -> some View {
        Section(header: ListHeader(Localized.Title.results)) {
            ForEach(viewModel.searchingCurrencies) { description in
                currencyRow(for: description)
            }
        }
    }
    
    @ViewBuilder private func recentCurrencies() -> some View {
        if !viewModel.availableRecentCurrencies.isEmpty {
            Section(header: ListHeader(Localized.Title.recentCurrencies)) {
                ForEach(viewModel.availableRecentCurrencies) { description in
                    currencyRow(for: description, canDelete: true)
                }
            }
        }
    }
    
    @ViewBuilder private func otherCurrencies() -> some View {
        Section(header: ListHeader(Localized.Title.otherCurrencies)) {
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

// MARK: - Previews -

struct CurrencySelectionScreen_Previews: PreviewProvider {
    static var previews: some View {
        CurrencySelectionScreen(
            viewModel: CurrencySelectionViewModel(
                isPresented: .constant(true),
                exchange: .mock
            )
        )
        .environmentObjectsForSession()
    }
}
