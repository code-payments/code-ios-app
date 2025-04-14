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
        poller = Poller(seconds: 60, fireImmediately: true) { [weak self] in
            Task {
                try await self?.fetchExchangeRates()
            }
        }
    }
    
    private func fetchExchangeRates() async throws {
        let snapshot = try await client.fetchExchangeRates()
        try database.insert(snapshot: snapshot)
//        cache(rates: rates, for: date)
//        set(rates: rates, date: date)
    }
}
