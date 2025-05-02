//
//  HistoryController.swift
//  Code
//
//  Created by Dima Bart on 2025-04-11.
//

import Foundation
import FlipcashCore

@MainActor
class HistoryController: ObservableObject {
    
    @Published var activities: [Activity] = []
    
    private let client: FlipClient
    private let database: Database
    private let owner: AccountCluster
    
    // MARK: - Init -
    
    init(container: Container, owner: AccountCluster) {
        self.client   = container.flipClient
        self.database = container.database
        self.owner    = owner
        
        refreshHistory()
    }
    
    // MARK: - Fetch -
    
    func refreshHistory() {
        Task {
            try await fetchHistory()
        }
    }
    
    private func fetchHistory() async throws {
        let activities = try await client.fetchTransactionHistory(owner: owner.authority.keyPair)
        trace(.success, components: "Fetched \(activities.count) activities")
        self.activities = activities
    }
}

extension HistoryController {
    static let mock = HistoryController(container: .mock, owner: .mock)
}
