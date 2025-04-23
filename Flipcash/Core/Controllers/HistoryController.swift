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
    private let session: Session
    
    // MARK: - Init -
    
    init(container: Container, session: Session) {
        self.client   = container.flipClient
        self.database = container.database
        self.session  = session
        
        refreshHistory()
    }
    
    // MARK: - Fetch -
    
    func refreshHistory() {
        Task {
            try await fetchHistory()
        }
    }
    
    private func fetchHistory() async throws {
        let activities = try await client.fetchTransactionHistory(owner: session.ownerKeyPair)
        trace(.success, components: "Fetched \(activities.count) activities")
        self.activities = activities
    }
}
