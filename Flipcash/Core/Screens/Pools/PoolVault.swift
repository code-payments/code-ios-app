//
//  PoolVault.swift
//  Code
//
//  Created by Dima Bart on 2023-05-05.
//

import Foundation
import FlipcashCore

@MainActor
class PoolVault {
    
    func poolAccount(for vault: PublicKey) -> PoolAccount? {
        Keychain.poolVaults?[vault.base58]
    }
        
    func insert(_ poolAccount: PoolAccount) {
        let key = poolAccount.cluster.vaultPublicKey.base58
        
        if var poolVaults = Keychain.poolVaults {
            poolVaults[key] = poolAccount
            Keychain.poolVaults = poolVaults
        } else {
            Keychain.poolVaults = [key: poolAccount]
        }
    }
    
    func remove(_ poolAccount: PoolAccount) {
        remove(poolAccount.cluster.vaultPublicKey)
    }
    
    func remove(_ poolVault: PublicKey) {
        Keychain.poolVaults?[poolVault.base58] = nil
    }
    
    func nuke() {
        Keychain.poolVaults = nil
    }
}

extension PoolVault {
    static func prettyPrinted() {
        if let keys = Keychain.poolVaults?.keys {
            print("Pool Vault Accounts (\(keys.count)):")
            print("  - \(keys.joined(separator: "\n"))")
        }
    }
}

// MARK: - Keychain -

private extension Keychain {
    
    @SecureCodable(.poolVaults, sync: true)
    static var poolVaults: [String: PoolAccount]? // Keyed by vault public key
}

// MARK: - Pool -

public struct PoolAccount: Codable, Hashable, Equatable {
    
    public let index: Int
    public let cluster: AccountCluster
    public let date: Date
    
    public init(mnemonic: MnemonicPhrase, index: Int) {
        self.init(
            index: index,
            cluster: AccountCluster(
                authority: .derive(
                    using: .pool(index: index),
                    mnemonic: mnemonic
                )
            )
        )
    }
    
    private init(index: Int, cluster: AccountCluster) {
        self.index = index
        self.cluster = cluster
        self.date = .now
    }
}
