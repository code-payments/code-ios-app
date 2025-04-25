//
//  CurrencySelectionViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class CurrencySelectionViewModel: ObservableObject {
    
    @Published var availableCurrencies: [CurrencyDescription] = []
    @Published var availableRecentCurrencies: [CurrencyDescription] = []
    
    @Published var searchText = ""
    @Published var isFocused = false
    
    var isPresented: Binding<Bool>
    
    var isSearching: Bool {
        !searchText.isEmpty
    }
    
    var searchingCurrencies: [CurrencyDescription] {
        let term = searchText.lowercased()
        return currencies.filter {
            $0.currency.rawValue.lowercased().contains(term) || $0.localizedName.lowercased().contains(term)
        }
    }
    
    private let kind: CurrencySelectionType
    private let ratesController: RatesController
    private let currencies: [CurrencyDescription]
    private var recentCurrencies: Set<CurrencyCode>
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, kind: CurrencySelectionType, ratesController: RatesController) {
        self.isPresented      = isPresented
        self.kind             = kind
        self.ratesController  = ratesController
        self.currencies       = CurrencyCode.allCurrencies(in: .current)
        self.recentCurrencies = LocalDefaults.storedRecentCurrencies ?? []
        
        addLocalToRecentsIfNeeded()
        updateAvailableCurrencies()
    }
    
    private func addLocalToRecentsIfNeeded() {
        if let isAdded = LocalDefaults.localCurrencyAdded, isAdded {
            // Don't add it again
        } else if let local = CurrencyCode.local() {
            insertRecent(local)
            LocalDefaults.localCurrencyAdded = true
        }
    }
    
    // MARK: - Recent Currencies -
    
    private func insertRecent(_ currency: CurrencyCode) {
        recentCurrencies.insert(currency)
        LocalDefaults.storedRecentCurrencies = recentCurrencies
        
        updateAvailableCurrencies()
    }
    
    func removeRecent(_ currency: CurrencyCode) {
        recentCurrencies.remove(currency)
        LocalDefaults.storedRecentCurrencies = recentCurrencies
        
        updateAvailableCurrencies()
    }
    
    private func updateAvailableCurrencies() {
        availableCurrencies = currencies.filter {
            !recentCurrencies.contains($0.currency)
        }
        
        availableRecentCurrencies = currencies.filter {
            recentCurrencies.contains($0.currency)
        }
    }
    
    // MARK: - Selection -
    
    func select(currency: CurrencyCode) {
        setSelectedCurrency(currency)
        
        isFocused = false
        isPresented.wrappedValue = false
        
        Task {
            try await Task.delay(milliseconds: 200)
            insertRecent(currency)
        }
    }
    
    private func setSelectedCurrency(_ currency: CurrencyCode) {
        switch kind {
        case .entry:
            ratesController.entryCurrency = currency
        case .balance:
            ratesController.balanceCurrency = currency
        }
    }
    
    // MARK: - Currency Appearance -
    
    func opacity(for currency: CurrencyCode) -> CGFloat {
        ratesController.rate(for: currency) != nil ? 1.0 : 0.3
    }
    
    func isSelectionDisabled(for currency: CurrencyCode) -> Bool {
        ratesController.rate(for: currency) == nil
    }
    
    func isCurrencyActive(_ currency: CurrencyCode) -> Bool {
        switch kind {
        case .entry:
            return currency == ratesController.entryCurrency
        case .balance:
            return currency == ratesController.balanceCurrency
        }
    }
}

// MARK: - Kind -

enum CurrencySelectionType {
    case entry
    case balance
}

// MARK: - LocalDefaults -

private enum LocalDefaults {
    
    @Defaults(.recentCurrencies)
    static var storedRecentCurrencies: Set<CurrencyCode>?
    
    @Defaults(.localCurrencyAdded)
    static var localCurrencyAdded: Bool?
}
