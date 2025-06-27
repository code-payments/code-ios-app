//
//  PoolVault.swift
//  Code
//
//  Created by Dima Bart on 2023-05-05.
//

import Foundation
import FlipcashCore

//@MainActor
//class PoolVault {
//    
//    func poolAccounts() -> [String: PoolAccount]? {
//        Keychain.poolAccounts
//    }
//    
//    func poolAccount(for id: PublicKey) -> PoolAccount? {
//        Keychain.poolAccounts?[id.base58]
//    }
//        
//    func insert(_ poolAccount: PoolAccount) {
//        let key = poolAccount.keychainKey.base58
//        
//        if var poolAccounts = Keychain.poolAccounts {
//            poolAccounts[key] = poolAccount
//            Keychain.poolAccounts = poolAccounts
//        } else {
//            Keychain.poolAccounts = [key: poolAccount]
//        }
//    }
//    
//    func remove(_ poolAccount: PoolAccount) {
//        remove(poolAccount.keychainKey)
//    }
//    
//    func remove(_ poolID: PublicKey) {
//        Keychain.poolAccounts?[poolID.base58] = nil
//    }
//    
//    func nuke() {
//        Keychain.poolAccounts = nil
//    }
//}
//
//private extension PoolAccount {
//    var keychainKey: PublicKey {
//        rendezvous.publicKey
//    }
//}
//
//extension PoolVault {
//    static func prettyPrinted() {
//        if let keys = Keychain.poolAccounts?.keys {
//            print("Pool Vault Accounts (\(keys.count)):")
//            print("  - \(keys.joined(separator: "\n"))")
//        }
//    }
//}
//
//// MARK: - Keychain -
//
//private extension Keychain {
//    
//    @SecureCodable(.poolAccounts, sync: true)
//    static var poolAccounts: [String: PoolAccount]? // Keyed by vault public key
//}
