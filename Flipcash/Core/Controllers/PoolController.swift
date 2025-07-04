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
    
    private let ratesController: RatesController
    
    private var ownerKeyPair: KeyPair {
        owner.authority.keyPair
    }
    
    // MARK: - Init -
    
    init(container: Container, ratesController: RatesController, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID, database: Database) {
        self.keyAccount = keyAccount
        self.owner      = owner
        self.userID     = userID
        self.client     = container.client
        self.flipClient = container.flipClient
        self.database   = database
        
        self.ratesController = ratesController
        
        Task {
            try await syncPools()
        }
    }
    
    // MARK: - Sync -
    
    func syncPools() async throws {
        try await syncPools(since: nil)
        try deriveMissingRendezvousKeys()
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
                    try $0.insertPool(pool: pool)
                    try $0.insertBets(poolID: pool.metadata.id, bets: pool.bets)
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
    
    @discardableResult
    func updatePool(poolID: PublicKey, rendezvous: KeyPair? = nil) async throws -> PoolMetadata {
        let pool = try await flipClient.fetchPool(poolID: poolID)
        
        var metadata = pool.metadata
        if let rendezvous, rendezvous.publicKey == poolID {
            metadata.rendezvous = rendezvous
        }
        
        try database.transaction {
            try $0.insertPool(pool: pool)
            try $0.insertBets(poolID: pool.metadata.id, bets: pool.bets)
        }
        
        return metadata
    }
    
    func createPool(name: String, buyIn: Fiat) async throws -> PublicKey {
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
            closedDate: nil,
            isOpen: true,
            name: name,
            buyIn: buyIn,
            resolution: nil
        )
        
        // Create the blockchain accounts
        // for this pool cluster
        try await client.createAccounts(
            owner: ownerKeyPair,
            cluster: poolAccount.cluster,
            kind: .pool,
            derivationIndex: poolAccount.index
        )
        
        // Create pool metadata
        try await flipClient.createPool(
            poolMetadata: metadata,
            owner: ownerKeyPair
        )
        
        // We don't want to surface any errors
        // from the update call during pool creation
        _ = try? await updatePool(
            poolID: metadata.id,
            rendezvous: metadata.rendezvous
        )
        
        return metadata.id
    }
    
    @discardableResult
    func createBet(poolMetadata: PoolMetadata, outcome: PoolResoltion) async throws -> BetMetadata {
        let poolID = poolMetadata.id
        
        // Bet IDs are always deterministically derived
        // so any subsequent payment attempts use the
        // same betID (ie. retries, etc)
        let betKeyPair = KeyPair.deriveBetID(
            poolID: poolID,
            userID: userID
        )
        
        let betID = betKeyPair.publicKey
        
        // 1. Create the bet on the server before
        // the payment is made
        let metadata = BetMetadata(
            id: betID,
            userID: userID,
            payoutDestination: owner.vaultPublicKey,
            betDate: .now,
            selectedOutcome: outcome
        )
        
        guard let rendezvous = poolMetadata.rendezvous else {
            throw Error.poolRendezvousMissing
        }
        
        try await flipClient.createBet(
            poolRendezvous: rendezvous,
            betMetadata: metadata,
            owner: ownerKeyPair
        )
        
        // 2. Get the current conversion rate
        // and pay for the bet buyIn
        guard let rate = ratesController.rate(for: poolMetadata.buyIn.currencyCode) else {
            throw Error.exchangeRateUnavailable
        }
        
        let exchangedFiat = try ExchangedFiat(
            converted: poolMetadata.buyIn,
            rate: rate
        )
        
        // 3. Pay for the bet. Any failure here can
        // be retried with the existing bet ID
        try await client.transfer(
            exchangedFiat: exchangedFiat,
            owner: owner,
            destination: poolMetadata.fundingAccount,
            rendezvous: betID // NOT the pool rendezvous, it's the intentID
        )
        
        _ = try? await updatePool(poolID: poolID)
        
        return metadata
    }
    
    func declareOutcome(poolMetadata: PoolMetadata, outcome: PoolResoltion) async throws {
        
        var updatedMetadata = poolMetadata
        if poolMetadata.isOpen {
            updatedMetadata.isOpen     = false
            updatedMetadata.closedDate = .now
            
            // First, close voting on the pool
            try await flipClient.closePool(
                poolMetadata: updatedMetadata,
                owner: ownerKeyPair
            )
        }
        
//        try await flipClient.fetchPool(poolID: updatedMetadata.id)
        

        
        // After closing, the pool rendezvous signature
        // was updated so we need to update our local
        // pool metadata
//        let closedPool = try await updatePool(poolID: poolMetadata.id)
        
        updatedMetadata.resolution = outcome
        
        // Declare the pool outcome
        try await flipClient.resolvePool(
            poolMetadata: updatedMetadata,
            owner: ownerKeyPair
        )
        
        // After the pool is resolved, it is updated so
        // so we'll need to refresh local pool metadata
        try await updatePool(poolID: poolMetadata.id)
    }
}

// MARK: - Errors -

extension PoolController {
    enum Error: Swift.Error {
        case nextPoolIndexNotFound
        case exchangeRateUnavailable
        case poolRendezvousMissing
    }
}

// MARK: - Mock -

extension PoolController {
    static let mock = PoolController(
        container: .mock,
        ratesController: .mock,
        keyAccount: .mock,
        owner: .mock,
        userID: UUID(),
        database: .mock
    )
}
