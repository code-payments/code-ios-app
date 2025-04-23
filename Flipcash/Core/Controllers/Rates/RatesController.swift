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
    
    @Published var entryCurrency: CurrencyCode   = .usd
    @Published var balanceCurrency: CurrencyCode = .usd
    
    private let client: Client
    private let database: Database
    
    private var poller: Poller!
    
    // MARK: - Init -
    
    init(container: Container) {
        self.client = container.client
        self.database = container.database
        
        registerPoller()
    }
    
    private func registerPoller() {
        poller = Poller(seconds: 55, fireImmediately: true) { [weak self] in
            Task {
                try await self?.fetchExchangeRates()
            }
        }
    }
    
    private func fetchExchangeRates() async throws {
        let snapshot = try await client.fetchExchangeRates()
        try database.insert(snapshot: snapshot)
    }
    
    // MARK: - Rates -
    
    func rate(for currency: CurrencyCode) -> Rate? {
        try? database.rate(for: currency)
    }
}
