//
//  AccountManager.swift
//  Code
//
//  Created by Dima Bart on 2022-03-02.
//

import UIKit
import FlipchatServices

@MainActor
class AccountManager {
    
    var accountCount: Int {
        Keychain.historicalAccounts?.count ?? 0
    }
    
    private var currentAccount: KeyAccount? {
        get {
            Keychain.keyAccount
        }
        set {
            Keychain.keyAccount = newValue
        }
    }
    
    private var currentUserID: UserID? {
        get {
            Keychain.userID
        }
        set {
            Keychain.userID = newValue
        }
    }
    
    private var currentUserFlags: UserFlags? {
        get {
            Keychain.userFlags
        }
        set {
            Keychain.userFlags = newValue
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
    
    func fetchCurrent() -> (account: KeyAccount?, userID: UserID?, userFlags: UserFlags?) {
        (currentAccount, currentUserID, currentUserFlags)
    }
    
    func set(account: KeyAccount, userID: UserID, userFlags: UserFlags) {
        currentAccount = account
        currentUserID = userID
        currentUserFlags = userFlags
        
        upsert(account: account)
    }
    
    func update(userFlags: UserFlags) {
        if currentUserFlags != nil {
            currentUserFlags = userFlags
        }
    }
    
    func upsert(account: KeyAccount) {
        let key = account.ownerPublicKey.base58
        
        let newDescription = AccountDescription(
            account: account,
            creationDate: Date()
        )
        
        if var historicalAccounts = Keychain.historicalAccounts {
            if var oldDescription = historicalAccounts[key] {
                oldDescription.markSeen()
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
    
    func delete(ownerPublicKey: PublicKey) {
        let key = ownerPublicKey.base58
        if
            var historicalAccounts = Keychain.historicalAccounts,
            var accountDescription = historicalAccounts[key]
        {
            accountDescription.markDeleted()
            historicalAccounts[key] = accountDescription
            Keychain.historicalAccounts = historicalAccounts
        }
    }
    
    func resetForLogout() {
        currentAccount = nil
        currentUserID = nil
        currentUserFlags = nil
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
    @SecureCodable(.accountCurrent)
    static var keyAccount: KeyAccount?
    
    @SecureCodable(.userCurrent)
    static var userID: UserID?
    
    @SecureCodable(.userFlags)
    static var userFlags: UserFlags?
    
    @SecureCodable(.accountList, sync: true)
    static var historicalAccounts: [String: AccountDescription]?
}

// MARK: - Container -

struct AccountDescription: Codable, Hashable, Equatable, Sendable {
    
    let account: KeyAccount
    let creationDate: Date
    var deletionDate: Date?
    var deviceName: String
    var lastSeen: Date
    
    // MARK: - Init -
    
    fileprivate init(account: KeyAccount, creationDate: Date, deletionDate: Date? = nil) {
        self.account = account
        self.deviceName = "iPhone"
        self.creationDate = creationDate
        self.deletionDate = deletionDate
        self.lastSeen = .now()
    }
    
    mutating fileprivate func markSeen() {
        lastSeen = .now()
    }
    
    mutating fileprivate func markDeleted() {
        deletionDate = .now()
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
                creationDate: .now().adding(days: -index)
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
