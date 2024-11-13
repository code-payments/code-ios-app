//
//  Secure.swift
//  Code
//
//  Created by Dima Bart on 2021-02-11.
//

import Foundation
import FlipchatServices

enum SecureKey: String {
    
    case userCurrent    = "com.flipchat.user.current"

    case accountCurrent = "com.flipchat.account.current"
    case accountList    = "com.flipchat.account.list"
    case betaEnabled    = "com.flipchat.beta.enabled"
    
    // Code keys
    
    case codeRestricted         = "com.code.account.restricted"
    case codeKeyAccount         = "com.code.account.key"
    case codeHistoricalAccounts = "com.code.account.list"
    case codeGiftCardAccounts   = "com.code.giftCard.list"
    case codeCurrentUser        = "com.code.user.current"
    case codeRates              = "com.code.exchange.rates"
    case codeDebugOptions       = "com.code.debug.options"
}

@MainActor
@propertyWrapper
struct SecureData {
    
    var wrappedValue: Data? {
        get {
            return Keychain.secure.data(for: key.rawValue)
        }
        set {
            if let newValue = newValue {
                Keychain.secure.set(newValue, for: key.rawValue)
            } else {
                Keychain.secure.delete(key.rawValue)
            }
        }
    }
    
    private let key: SecureKey
    
    init(_ key: SecureKey) {
        self.key = key
    }
}

@MainActor
@propertyWrapper
struct SecureString {
    
    var wrappedValue: String? {
        get {
            return Keychain.secure.string(for: key.rawValue)
        }
        set {
            if let newValue = newValue {
                Keychain.secure.set(newValue, for: key.rawValue)
            } else {
                Keychain.secure.delete(key.rawValue)
            }
        }
    }
    
    private let key: SecureKey
    
    init(_ key: SecureKey) {
        self.key = key
    }
}

@MainActor
@propertyWrapper
struct SecureCodable<T> where T: Codable {
    
    var wrappedValue: T? {
        get {
            decode(Keychain.secure.data(for: key.rawValue))
        }
        set {
            if let newValue = encode(newValue) {
                Keychain.secure.set(newValue, for: key.rawValue, useSynchronization: sync)
            } else {
                Keychain.secure.delete(key.rawValue)
            }
        }
    }
    
    private let key: SecureKey
    private let sync: Bool
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Init -
    
    init(_ key: SecureKey, sync: Bool = false) {
        self.key = key
        self.sync = sync
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

private extension Keychain {
    static let secure = Keychain()
}
