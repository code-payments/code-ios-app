//
//  Exchange.swift
//  Code
//
//  Created by Dima Bart on 2021-02-22.
//

import Foundation
import CodeUI
import CodeServices

@MainActor
class Exchange: ObservableObject {
    
    @Published private(set) var entryRate: Rate = .oneToOne
    @Published private(set) var localRate: Rate = .oneToOne
    @Published private(set) var deviceRate: Rate = .oneToOne
    @Published private(set) var rateDate: Date = Date(timeIntervalSince1970: 0)
    
    private let client: Client
    
    @SecureCodable(.rates) private var storedRates: RatesBox?
    
    @Defaults(.entryCurrency) private var entryCurrency: CurrencyCode?
    @Defaults(.localCurrency) private var localCurrency: CurrencyCode?
    
    private var poller: Poller!
    
    private var rates: RatesBox = RatesBox()
    
    private var isStale: Bool {
        // Remember, the exchange rates date is the server-provided
        // date-of-rate and not the time the rate was fetched. It
        // might be reasonable for the server to return a date that
        // is dated 11 minutes or older.
        rates.date.minutesBetween(date: .now()) > 20
    }
    
    // MARK: - Init -
    
    init(client: Client) {
        self.client = client
        
        loadCachedRatesIfNeeded()
        
        registerPoller()
        
        Task {
            try await fetchRatesIfNeeded()
        }
    }
    
    private func registerPoller() {
        poller = Poller(seconds: 60) { [weak self] in
            Task {
                try await self?.fetchExchangeRates()
            }
        }
    }
    
    private func loadCachedRatesIfNeeded() {
        if let box = cachedRates() {
            trace(.cache, components: "Successfully loaded \(box.rates.count) cached exchange rates. Staleness \(box.date.minutesBetween(date: .now())) min")
            set(ratesBox: box)
        }
    }
    
    private func fetchExchangeRates() async throws {
        let (rates, date) = try await client.fetchExchangeRates()
        cache(rates: rates, for: date)
        set(rates: rates, date: date)
    }
    
    func fetchRatesIfNeeded() async throws {
        if isStale {
            trace(.warning, components: "Exchange rates are \(rates.date.minutesBetween(date: .now())) min old, which is considered stale.")
            try await fetchExchangeRates()
        }
    }
    
    // MARK: - Setters -
    
    func setEntryCurrency(_ currency: CurrencyCode) {
        entryCurrency = currency
        updateRates()
    }
    
    func setLocalCurrency(_ currency: CurrencyCode) {
        localCurrency = currency
        updateRates()
    }
    
    // MARK: - Update -
    
    private func set(rates: [Rate], date: Date) {
        set(ratesBox: RatesBox(date: date, rates: rates))
    }
    
    private func set(ratesBox: RatesBox) {
        rates = ratesBox
        rateDate = ratesBox.date
        
        setLocalCurrencyIfNeeded()
        setEntryCurrencyToLocalIfNeeded()
        
        updateRates()
    }
    
    private func setLocalCurrencyIfNeeded() {
        guard localCurrency == nil else {
            // Only set a local currency the first
            // time when it hasn't been set yet
            return
        }
        
        guard let currency = CurrencyCode.local() else {
            return
        }
        
        localCurrency = currency
    }
    
    private func setEntryCurrencyToLocalIfNeeded() {
        guard entryCurrency == nil else {
            // Only set a default currency
            // if one is not already set
            return
        }
        
        guard let localRegionCurrency = CurrencyCode.local() else {
            return
        }
        
        entryCurrency = localRegionCurrency
    }
    
    private func updateRates() {
        guard !rates.isEmpty else {
            return
        }
        
        if let currency = localCurrency {
            if let rate = rates.rate(for: currency) {
                localRate = rate
                trace(.note, components: "Updated the local currency: \(currency)", "Staleness \(rates.date.minutesBetween(date: .now())) min", "Date: \(rates.date.formatted())")
            } else {
                // If a rate for a local currency isn't found,
                // default to US currency and region
                localRate = rates.rateForUSD()
                trace(.failure, components: "Rate for local \(currency) not found. Defaulting to USD.")
            }
        }
        
        if let currency = entryCurrency {
            if let rate = rates.rate(for: currency) {
                entryRate = rate
                trace(.note, components: "Updated the entry currency: \(currency)", "Staleness \(rates.date.minutesBetween(date: .now())) min", "Date: \(rates.date.formatted())")
            } else {
                // If a rate for an entry currency isn't found,
                // default to US currency and region
                entryRate = rates.rateForUSD()
                trace(.failure, components: "Rate for entry \(currency) not found. Defaulting to USD.")
            }
        }
        
        // Assign current device locale rate,
        // it should only ever change with
        // the system locale
        deviceRate = rates.rate(for: CurrencyCode.local() ?? .usd) ?? rates.rateForUSD()
        
        ErrorReporting.breadcrumb(
            name: "[Background] Updated rates",
            metadata: [
                "date": rates.date.description,
            ],
            type: .process
        )
    }
    
    func rate(for currency: CurrencyCode) -> Rate? {
        rates.rate(for: currency)
    }
    
    func hasRate(for currency: CurrencyCode) -> Bool {
        rates.rate(for: currency) != nil
    }
    
    // MARK: - Cache -
    
    private func cache(rates: [Rate], for date: Date) {
        storedRates = RatesBox(
            date: date,
            rates: rates
        )
    }
    
    private func cachedRates() -> RatesBox? {
        storedRates
    }
}

extension Date {
    func secondsBetween(date: Date) -> Int {
        let lhs = self.timeIntervalSince1970
        let rhs = date.timeIntervalSince1970
        
        let diff = abs(lhs - rhs)
        return Int(diff)
    }
    
    func minutesBetween(date: Date) -> Int {
        secondsBetween(date: date) / 60
    }
}

// MARK: - Container -

private struct RatesBox: Codable {
    
    let date: Date
    let rates: [CurrencyCode: Rate]
    
    var isEmpty: Bool {
        rates.isEmpty
    }
    
    init(date: Date = Date(timeIntervalSince1970: 0), rates: [Rate] = []) {
        var index: [CurrencyCode: Rate] = [:]
        rates.forEach { rate in
            index[rate.currency] = rate
        }
        
        self.date  = date
        self.rates = index
    }
    
    func rate(for currency: CurrencyCode) -> Rate? {
        rates[currency]
    }
    
    func rateForUSD() -> Rate {
        rate(for: .usd)!
    }
}

// MARK: - Mock -

extension Exchange {
    static let mock = Exchange(client: .mock)
}
