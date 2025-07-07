//
//  RatesController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore

@MainActor
class RatesController: ObservableObject {
    
    @Published var entryCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.entryCurrency = newValue
        }
    }
    
    @Published var balanceCurrency: CurrencyCode = .usd {
        willSet {
            LocalDefaults.balanceCurrency = newValue
        }
    }
    
    private let client: Client
    private let database: Database
    
    private var poller: Poller!
    
    // MARK: - Init -
    
    init(container: Container, database: Database) {
        self.client   = container.client
        self.database = database
        
        if LocalDefaults.entryCurrency == nil {
            LocalDefaults.entryCurrency = .local() ?? .usd
        }
        
        if LocalDefaults.balanceCurrency == nil {
            LocalDefaults.balanceCurrency = .local() ?? .usd
        }
        
        entryCurrency   = LocalDefaults.entryCurrency!
        balanceCurrency = LocalDefaults.balanceCurrency!
        
        registerPoller()
    }
    
    // MARK: - Poller -
    
    private func registerPoller() {
        poller = Poller(seconds: 55, fireImmediately: true) { [weak self] in
            Task {
                try await self?.poll()
            }
        }
    }
    
    private func poll() async throws {
        try await fetchExchangeRates()
    }
    
    // MARK: - Rates -
    
    
    private func fetchExchangeRates() async throws {
        let snapshot = try await client.fetchExchangeRates()
        try database.insert(snapshot: snapshot)
    }
    
    func rateForBalanceCurrency() -> Rate {
        rate(for: balanceCurrency) ?? .oneToOne
    }
    
    func rateForEntryCurrency() -> Rate {
        rate(for: entryCurrency) ?? .oneToOne
    }
    
    func rate(for currency: CurrencyCode) -> Rate? {
        try? database.rate(for: currency)
    }
    
    func exchangedFiat(for amount: Fiat) throws -> ExchangedFiat {
        guard let rate = rate(for: amount.currencyCode) else {
            throw Error.exchangeRateUnavailable
        }
        
        let exchangedFiat = try ExchangedFiat(
            converted: amount,
            rate: rate
        )
        
        return exchangedFiat
    }
}

// MARK: - Errors -

extension RatesController {
    enum Error: Swift.Error {
        case exchangeRateUnavailable
    }
}

// MARK: - LocalDefaults -

private enum LocalDefaults {
    @Defaults(.entryCurrency)
    static var entryCurrency: CurrencyCode?
    
    @Defaults(.balanceCurrency)
    static var balanceCurrency: CurrencyCode?
}

extension RatesController {
    static let mock = RatesController(container: .mock, database: .mock)
}
