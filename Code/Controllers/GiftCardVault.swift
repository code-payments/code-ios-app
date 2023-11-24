//
//  GiftCardVault.swift
//  Code
//
//  Created by Dima Bart on 2023-05-05.
//

import Foundation
import CodeServices

@MainActor
class GiftCardVault {
    
    func giftCard(for vault: PublicKey) -> GiftCardAccount? {
        Keychain.giftCardAccounts?[vault.base58]
    }
        
    func insert(_ giftCard: GiftCardAccount) {
        if var giftCards = Keychain.giftCardAccounts {
            giftCards[giftCard.keychainKey] = giftCard
            Keychain.giftCardAccounts = giftCards
        } else {
            Keychain.giftCardAccounts = [giftCard.keychainKey: giftCard]
        }
    }
    
    func remove(_ giftCard: GiftCardAccount) {
        Keychain.giftCardAccounts?[giftCard.keychainKey] = nil
    }
    
    func nuke() {
        Keychain.giftCardAccounts = nil
    }
}

extension GiftCardVault {
    static func prettyPrinted() {
        if let keys = Keychain.giftCardAccounts?.keys {
            print("Gift Card Vault Accounts (\(keys.count)):")
            print("  - \(keys.joined(separator: "\n"))")
        }
    }
}

// MARK: - Key -

private extension GiftCardAccount {
    var keychainKey: String {
        cluster.timelockAccounts.vault.publicKey.base58
    }
}

// MARK: - Keychain -

private extension Keychain {
    
    @SecureCodable(.giftCardAccounts, sync: true)
    static var giftCardAccounts: [String: GiftCardAccount]? // Keyed by vault public key
}
