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
    
//    @Published var activities: [Activity] = []
    
    private let client: FlipClient
    private let database: Database
    private let owner: AccountCluster
    
    private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
    // MARK: - Init -
    
    init(container: Container, database: Database, owner: AccountCluster) {
        self.client   = container.flipClient
        self.database = database
        self.owner    = owner
        
        sync()
    }
    
    // MARK: - Fetch -
    
    func sync() {
        Task {
            try await syncDeltaHistory()
            try await syncPendingActivities()
        }
    }
    
    private func syncDeltaHistory() async throws {
        let latestID = try database.getLatestActivityID()
        try await syncHistory(since: latestID)
    }
    
    private func syncPendingActivities() async throws {
        let pendingIDs = try database.getPendingActivityIDs()
        if !pendingIDs.isEmpty {
            let activities = try await client.fetchTransactionHistoryItemsByID(owner: ownerKeyPair, ids: pendingIDs)
            try database.transaction {
                try $0.insertActivities(activities: activities)
            }
            
            trace(.success, components: "Inserted \(activities.count) pending activities")
        } else {
            trace(.note, components: "No pending activities")
        }
    }
    
    private func syncHistory(since id: PublicKey? = nil) async throws {
        let pageSize = 1024
        var cursor: PublicKey? = id
        
        var container: [Activity] = []
        
        var hasMore = true
        while hasMore {
            let activities = try await client.fetchTransactionHistory(
                owner: ownerKeyPair,
                pageSize: pageSize,
                since: cursor
            )
            
            if !activities.isEmpty {
                container.append(contentsOf: activities)
                cursor = activities.last!.id
            }
            
            hasMore = activities.count == pageSize
        }

        if !container.isEmpty {
            try database.transaction {
                try $0.insertActivities(activities: container)
            }
            
            trace(.success, components: "Inserted \(container.count) activities")
        } else {
            trace(.success, components: "No new activities")
        }
    }
}

extension HistoryController {
    static let mock = HistoryController(container: .mock, database: .mock, owner: .mock)
}
