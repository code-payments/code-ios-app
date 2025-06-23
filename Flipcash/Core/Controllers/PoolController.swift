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
    private let poolVault: PoolVault
    
    // MARK: - Init -
    
    init(container: Container, keyAccount: KeyAccount, owner: AccountCluster, userID: UserID, database: Database) {
        self.keyAccount = keyAccount
        self.owner      = owner
        self.userID     = userID
        self.client     = container.client
        self.flipClient = container.flipClient
        self.database   = database
        self.poolVault  = PoolVault()
    }
    
    // MARK: - Pools -
    
    func createPool(name: String, buyIn: Fiat) async throws -> PoolMetadata {
        let info = try await client.fetchAccountInfo(
            type: .primary,
            owner: owner.authority.keyPair
        )
        
        guard let nextIndex = info.nextPoolIndex else {
            throw Error.nextPoolIndexNotFound
        }
        
        let rendezvous = KeyPair.generate()!
        let poolAccount = PoolAccount(
            mnemonic: keyAccount.mnemonic,
            index: nextIndex
        )
        
        let metadata = PoolMetadata(
            id: rendezvous.publicKey,
            rendezvous: rendezvous,
            fundingAccount: poolAccount.cluster.vaultPublicKey,
            creatorUserID: userID,
            creationDate: .now,
            isOpen: true,
            name: name,
            buyIn: buyIn,
            resolution: nil
        )
        
        try await flipClient.createPool(
            poolMetadata: metadata,
            owner: owner.authority.keyPair
        )
        
        // Store pool private key so
        // that we can retrieve on another
        // device or across app installs
        poolVault.insert(poolAccount)
        
        try database.transaction {
            try $0.insertPool(metadata: metadata)
        }
        
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
