//
//  PoolController.swift
//  Code
//
//  Created by Dima Bart on 2025-06-20.
//

import Foundation
import FlipcashCore

@MainActor
class PoolController: ObservableObject {
    
    private let keyAccount: KeyAccount
    private let owner: AccountCluster
    private let userID: UserID
    private let client: Client
    private let flipClient: FlipClient
    private let database: Database
    
    private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
    // MARK: - Init -
    
    init(container: Container, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID, database: Database) {
        self.keyAccount = keyAccount
        self.owner      = owner
        self.userID     = userID
        self.client     = container.client
        self.flipClient = container.flipClient
        self.database   = database
        
        Task {
            try await syncPools()
            
            try deriveMissingRendezvousKeys()
        }
    }
    
    // MARK: - Sync -
    
    func syncPools() async throws {
        try await syncPools(since: nil)
    }
    
    private func syncPools(since cursorID: ID? = nil) async throws {
        let pageSize = 1024
        var cursor: ID? = cursorID
        
        // 1. Fetch all pool description pages
        // that are available on the server
        var pools: [PoolDescription] = []
        
        var hasMore = true
        while hasMore {
            let poolDescriptions = try await flipClient.fetchPools(
                owner: ownerKeyPair,
                pageSize: 1024,
                since: cursor
            )
            
            if !poolDescriptions.isEmpty {
                pools.append(contentsOf: poolDescriptions)
                cursor = poolDescriptions.last!.cursor
            }
            
            hasMore = poolDescriptions.count == pageSize
        }
        
        // 2. Verify pool metadata and discard any that
        // are don't pass validation
        pools = pools.filter { _ in
            // TODO: Verify signatures for pools and bets
            return true
        }

        // 3. Store all pools and bets
        if !pools.isEmpty {
            try database.transaction {
                for pool in pools {
                    try $0.insertPool(metadata: pool.metadata, additionalInfo: pool.additionalInfo)
                    try $0.insertBets(poolID: pool.metadata.id, bets: pool.bets.map { $0.metadata })
                }
            }
            
            trace(.success, components: "Inserted \(pools.count) pools")
        } else {
            trace(.success, components: "No pools")
        }
    }
    
    private func deriveMissingRendezvousKeys() throws {
        guard let keysAndIndexes = try? database.getHostedPoolsWithoutRendezvousKeys(hostID: userID), !keysAndIndexes.isEmpty else {
            print("[PoolController] Rendezvous keys up-to-date")
            return
        }
        
        let mnemonic = keyAccount.mnemonic
        var keys: [KeyPair] = []
        
        keysAndIndexes.forEach { (publicKey, index) in
            let account = PoolAccount(mnemonic: mnemonic, index: index)
            if account.rendezvous.publicKey == publicKey {
                keys.append(account.rendezvous)
            }
        }
        
        if !keys.isEmpty {
            print("[PoolController] Derived \(keys.count) missing rendezvous keys")
            try assignRendezvousKeys(keys: keys)
        }
    }
    
//    private func findRendezvousKeysIfNeeded() {
//        guard let keysToFind = try? database.getHostedPoolsWithoutRendezvousKeys(hostID: userID) else {
//            return
//        }
//        
//        Task.detached(priority: .background) { [weak self] in
//            guard let self = self else { return }
//            
//            let keys = findRendezvousKeys(for: keysToFind)
//            try await assignRendezvousKeys(keys: keys)
//        }
//    }
//    
//    nonisolated
//    private func findRendezvousKeys(for ids: [PublicKey]) -> [PublicKey: KeyPair] {
//        let start = Date.now
//        
//        // The public keys of all the
//        // rendezvous keys we need to find
//        var rendezvousToFind = Set(ids)
//        var foundKeyPairs: [PublicKey: KeyPair] = [:]
//        
//        let mnemonic = keyAccount.mnemonic
//        for i in 0...2048 {
//            let account   = PoolAccount(mnemonic: mnemonic, index: i)
//            let accountID = account.rendezvous.publicKey
//            
//            if rendezvousToFind.remove(accountID) != nil {
//                foundKeyPairs[accountID] = account.rendezvous
//            }
//            
//            if rendezvousToFind.isEmpty {
//                break
//            }
//        }
//        
//        print("[PoolController] findRendezvousKeys took: \(Date.now.formattedMilliseconds(from: start)) ")
//        return foundKeyPairs
//    }
    
    private func assignRendezvousKeys(keys: [KeyPair]) throws {
        try database.transaction {
            for rendezvous in keys {
                try $0.setRendezvousForPool(rendezvous: rendezvous)
            }
        }
    }
    
    // MARK: - Pools -
    
    // TODO: Insert pool from link
    
    func updatePool(poolID: PublicKey, rendezvous: KeyPair? = nil) async throws {
        let pool = try await flipClient.fetchPool(poolID: poolID)
        
        var metadata = pool.metadata
        if let rendezvous, rendezvous.publicKey == poolID {
            metadata.rendezvous = rendezvous
        }
        
        try database.transaction {
            try $0.insertPool(metadata: metadata, additionalInfo: pool.additionalInfo)
            try $0.insertBets(poolID: pool.metadata.id, bets: pool.bets.map { $0.metadata })
        }
    }
    
    func createPool(name: String, buyIn: Fiat) async throws {
        let info = try await client.fetchAccountInfo(
            type: .primary,
            owner: ownerKeyPair
        )
        
        guard let nextIndex = info.nextPoolIndex else {
            throw Error.nextPoolIndexNotFound
        }
        
        let poolAccount = PoolAccount(
            mnemonic: keyAccount.mnemonic,
            index: nextIndex
        )
        
        let metadata = PoolMetadata(
            id: poolAccount.rendezvous.publicKey,
            rendezvous: poolAccount.rendezvous,
            fundingAccount: poolAccount.cluster.vaultPublicKey,
            creatorUserID: userID,
            creationDate: .now,
            isOpen: true,
            name: name,
            buyIn: buyIn,
            resolution: nil
        )
        
        // TODO: Create blockchain accounts
//        try await client.createAccounts(
//            with: poolAccount.cluster,
//            kind: .pool
//        )
        
        // Create pool metadata
        try await flipClient.createPool(
            poolMetadata: metadata,
            owner: ownerKeyPair
        )
        
        // We don't want to surface any errors
        // from the update call during pool creation
        try? await updatePool(
            poolID: metadata.id,
            rendezvous: metadata.rendezvous
        )
    }
    
    @discardableResult
    func createBet(poolRendezvous: KeyPair, outcome: BetOutcome) async throws -> BetMetadata {
        let poolID = poolRendezvous.publicKey
        
        let betKeyPair = KeyPair.deriveBetID(
            poolID: poolID,
            userID: userID
        )
        
        let metadata = BetMetadata(
            id: betKeyPair.publicKey,
            userID: userID,
            payoutDestination: owner.vaultPublicKey,
            betDate: .now,
            selectedOutcome: outcome
        )
        
        try await flipClient.createBet(
            poolRendezvous: poolRendezvous,
            betMetadata: metadata,
            owner: ownerKeyPair
        )
        
        // TODO: Pay for bet
        
        // TODO: Fulfill bet in database
//        try database.transaction {
//            try $0.setBetFulfilled(betID: betID)
//        }
        
        try? await updatePool(poolID: poolID)
        
        return metadata
    }
}

// MARK: - Errors -

extension PoolController {
    enum Error: Swift.Error {
        case nextPoolIndexNotFound
    }
}

// MARK: - Mock -

extension PoolController {
    static let mock = PoolController(
        container: .mock,
        keyAccount: .mock,
        owner: .mock,
        userID: UUID(),
        database: .mock
    )
}
