//
//  CurrencySelectionViewModel.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor @Observable
class CurrencySelectionViewModel {

    var availableCurrencies: [CurrencyDescription] = []
    var availableRecentCurrencies: [CurrencyDescription] = []

    var searchText = ""
    var isFocused = false

    var isSearching: Bool {
        !searchText.isEmpty
    }

    var searchingCurrencies: [CurrencyDescription] {
        let term = searchText.lowercased()
        return currencies.filter {
            $0.currency.rawValue.lowercased().contains(term) || $0.localizedName.lowercased().contains(term)
        }
    }

    @ObservationIgnored private let ratesController: RatesController
    @ObservationIgnored private let currencies: [CurrencyDescription]
    @ObservationIgnored private var recentCurrencies: Set<CurrencyCode>

    // MARK: - Init -

    init(ratesController: RatesController) {
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
        ratesController.balanceCurrency = currency
        isFocused = false

        Task {
            try await Task.delay(milliseconds: 200)
            insertRecent(currency)
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
        currency == ratesController.balanceCurrency
    }
}

// MARK: - LocalDefaults -

private enum LocalDefaults {

    @Defaults(.recentCurrencies)
    static var storedRecentCurrencies: Set<CurrencyCode>?

    @Defaults(.localCurrencyAdded)
    static var localCurrencyAdded: Bool?
}
