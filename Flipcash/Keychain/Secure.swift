//
//  Secure.swift
//  Code
//
//  Created by Dima Bart on 2021-02-11.
//

import Foundation
import FlipcashCore

enum SecureKey: String {
    case historicalAccounts = "com.flipcash.account.list"
    case currentUserAccount = "com.flipcash.account.userAccount"
    case betaFlagsEnabled   = "com.flipcash.betaFlags.enabled"

    case connectedWalletSession = "com.flipcash.wallet.connectedSession"
}

@propertyWrapper
struct SecureString {
    
    var wrappedValue: String? {
        get {
            return Keychain.string(for: key.rawValue)
        }
        set {
            if let newValue = newValue {
                Keychain.set(newValue, for: key.rawValue)
            } else {
                Keychain.delete(key.rawValue)
            }
        }
    }
    
    private let key: SecureKey
    
    init(_ key: SecureKey) {
        self.key = key
    }
}

@propertyWrapper
struct SecureCodable<T> where T: Codable {

    var wrappedValue: T? {
        get {
            if sharedGroup {
                // Read from the shared access group first, then fall back to
                // the legacy groupless item. The fallback is the zero-logout
                // guarantee: an existing user whose owner key predates the
                // shared group still authenticates on upgrade.
                let group = Keychain.sharedAccessGroup
                if let group, let data = Keychain.data(for: key.rawValue, accessGroup: group) {
                    return decode(data)
                }
                return decode(Keychain.data(for: key.rawValue))
            } else {
                return decode(Keychain.data(for: key.rawValue))
            }
        }
        set {
            let group = sharedGroup ? Keychain.sharedAccessGroup : nil
            if let newValue = encode(newValue) {
                Keychain.set(newValue, for: key.rawValue, useSynchronization: sync, accessGroup: group)
            } else {
                Keychain.delete(key.rawValue, accessGroup: group)
                if sharedGroup {
                    // Also clear any legacy copy. A groupless delete spans every
                    // accessible access group, so a stale pre-migration item
                    // can't survive logout and resurrect via the fallback read.
                    Keychain.delete(key.rawValue)
                }
            }
        }
    }

    private let key: SecureKey
    private let sync: Bool
    private let sharedGroup: Bool

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Init -

    init(_ key: SecureKey, sync: Bool = false, sharedGroup: Bool = false) {
        self.key = key
        self.sync = sync
        self.sharedGroup = sharedGroup
    }
    
    // MARK: - Codable -
    
    private func encode(_ value: T?) -> Data? {
        guard let value = value else {
            return nil
        }
        
        return try? encoder.encode(value)
    }
    
    private func decode(_ data: Data?) -> T? {
        guard let data = data else {
            return nil
        }
        
        return try? decoder.decode(T.self, from: data)
    }
}
