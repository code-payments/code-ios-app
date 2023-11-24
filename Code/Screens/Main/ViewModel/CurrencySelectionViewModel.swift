//
//  CurrencySelectionViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import UIKit
import CodeServices
import CodeUI
import SwiftUI

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
    
    private let exchange: Exchange
    private let currencies: [CurrencyDescription]
    private var recentCurrencies: Set<CurrencyCode>
    
    @Defaults(.recentCurrencies) private static var storedRecentCurrencies: Set<CurrencyCode>?
    @Defaults(.localCurrencyAdded) private static var localCurrencyAdded: Bool?
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, exchange: Exchange) {
        self.isPresented = isPresented
        self.exchange   = exchange
        self.currencies = CurrencyCode.allCurrencies(in: .current)
        self.recentCurrencies = Self.storedRecentCurrencies ?? []
        
        addLocalToRecentsIfNeeded()
        updateAvailableCurrencies()
    }
    
    private func addLocalToRecentsIfNeeded() {
        if let isAdded = Self.localCurrencyAdded, isAdded {
            // Don't add it again
        } else if let local = CurrencyCode.local() {
            insertRecent(local)
            Self.localCurrencyAdded = true
        }
    }
    
    // MARK: - Recent Currencies -
    
    private func insertRecent(_ currency: CurrencyCode) {
        recentCurrencies.insert(currency)
        Self.storedRecentCurrencies = recentCurrencies
        
        updateAvailableCurrencies()
    }
    
    func removeRecent(_ currency: CurrencyCode) {
        recentCurrencies.remove(currency)
        Self.storedRecentCurrencies = recentCurrencies
        
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
        exchange.set(currency: currency)
        isFocused = false
        Task {
            try await Task.delay(milliseconds: 200)
            isPresented.wrappedValue = false
            
            // We don't want to see the animation
            // when inserting recent items
            try await Task.delay(milliseconds: 200)
            insertRecent(currency)
        }
    }
    
    // MARK: - Currency Appearance -
    
    func opacity(for currency: CurrencyCode) -> CGFloat {
        exchange.hasRate(for: currency) ? 1.0 : 0.3
    }
    
    func isSelectionDisabled(for currency: CurrencyCode) -> Bool {
        !exchange.hasRate(for: currency)
    }
    
    func isCurrencyActive(_ currency: CurrencyCode) -> Bool {
        currency == exchange.entryRate.currency
    }
}
