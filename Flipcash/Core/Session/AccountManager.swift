//
//  AccountManager.swift
//  Code
//
//  Created by Dima Bart on 2022-03-02.
//

import UIKit
import FlipcashCore

@MainActor
class AccountManager {
    
    var accountCount: Int {
        Keychain.historicalAccounts?.count ?? 0
    }
    
    private var currentKeyAccount: KeyAccount? {
        get {
            Keychain.keyAccount
        }
        set {
            Keychain.keyAccount = newValue
        }
    }
    
    private var currentUserAccount: UserAccount? {
        get {
            Keychain.userAccount
        }
        set {
            Keychain.userAccount = newValue
        }
    }
    
    // MARK: - Init -
    
    init() {}
    
    func fetchHistorical() -> [AccountDescription] {
        guard let map = Keychain.historicalAccounts else {
            return []
        }
        
        return Array(map.values).sorted { lhs, rhs in
            lhs.creationDate > rhs.creationDate
        }
    }
    
    func fetchCurrentUserAccount() -> UserAccount? {
        currentUserAccount
    }
    
    func set(keyAccount: KeyAccount, userID: UserID) {
        currentKeyAccount = keyAccount
        currentUserAccount = UserAccount(
            userID: userID,
            keyAccount: keyAccount
        )
        
        upsert(keyAccount: keyAccount)
    }
    
    func upsert(keyAccount: KeyAccount) {
        let key = keyAccount.ownerPublicKey.base58
        
        let newDescription = AccountDescription(
            account: keyAccount,
            creationDate: Date()
        )
        
        if var historicalAccounts = Keychain.historicalAccounts {
            if var oldDescription = historicalAccounts[key] {
                oldDescription.lastSeen = .now
                oldDescription.deletionDate = nil // Undelete
                historicalAccounts[key] = oldDescription
            } else {
                historicalAccounts[key] = newDescription
            }
            
            trace(.cache, components: "Storing private key in historical list.")
            Keychain.historicalAccounts = historicalAccounts
            
        } else {
            trace(.cache, components: "Storing private key in historical list. (first)")
            Keychain.historicalAccounts = [key: newDescription]
        }
    }
    
    func setDeleted(ownerPublicKey: PublicKey, deleted: Bool) {
        let key = ownerPublicKey.base58
        if
            var historicalAccounts = Keychain.historicalAccounts,
            var accountDescription = historicalAccounts[key]
        {
            if deleted {
                accountDescription.deletionDate = .now
            } else {
                accountDescription.deletionDate = nil
            }
            historicalAccounts[key] = accountDescription
            Keychain.historicalAccounts = historicalAccounts
        }
    }
    
    func resetForLogout() {
        currentKeyAccount = nil
        currentUserAccount = nil
    }
    
    func nuke() {
        resetForLogout()
        Keychain.historicalAccounts = nil
    }
    
    static func fetchDescription(for publicKey: PublicKey) -> AccountDescription? {
        let key = publicKey.base58
        
        guard let accounts = Keychain.historicalAccounts else {
            return nil
        }
        
        return accounts[key]
    }
}

// MARK: - Keychain -

private extension Keychain {
    @SecureCodable(.keyAccount)
    static var keyAccount: KeyAccount?
    
    @SecureCodable(.currentUserAccount)
    static var userAccount: UserAccount?
    
    @SecureCodable(.historicalAccounts, sync: true)
    static var historicalAccounts: [String: AccountDescription]?
}

// MARK: - Container -

struct AccountDescription: Codable, Hashable, Equatable, Sendable {
    
    let account: KeyAccount
    let creationDate: Date
    var deletionDate: Date?
    var lastSeen: Date
    
    // MARK: - Init -
    
    fileprivate init(account: KeyAccount, creationDate: Date, deletionDate: Date? = nil) {
        self.account = account
        self.creationDate = creationDate
        self.deletionDate = deletionDate
        self.lastSeen = .now
    }
    
    // MARK: - Hashable & Equatable -
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(account)
    }
    
    static func ==(lhs: AccountDescription, rhs: AccountDescription) -> Bool {
        lhs.account == rhs.account
    }
}

extension AccountDescription: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        "\(creationDate) - \(account.ownerPublicKey)"
    }
    
    var debugDescription: String {
        description
    }
}

extension AccountDescription {
    static func mockMany() -> [AccountDescription] {
        (0..<32).map { index in
            AccountDescription(
                account: createKeyAccount(),
                creationDate: .now.adding(days: -index)
            )
        }
    }
    
    private static func createKeyAccount() -> KeyAccount {
        let mnemonic = MnemonicPhrase.generate(.words12)
        let keyPair = KeyPair(mnemonic: mnemonic, path: .solana)
        let derivedKey = DerivedKey(path: .solana, keyPair: keyPair)
        return KeyAccount(
            mnemonic: mnemonic,
            derivedKey: derivedKey
        )
    }
}
