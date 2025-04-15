//
//  Secure.swift
//  Code
//
//  Created by Dima Bart on 2021-02-11.
//

import Foundation
import FlipcashCore

enum SecureKey: String {
    case keyAccount         = "com.flipcash.account.key"
    case historicalAccounts = "com.flipcash.account.list"
    case currentUser        = "com.flipcash.user.current"
//    case restricted = "com.code.account.restricted"
//    case giftCardAccounts = "com.code.giftCard.list"
    
//    case rates = "com.code.exchange.rates"
//    case debugOptions = "com.code.debug.options"
}

@propertyWrapper
struct SecureData {
    
    var wrappedValue: Data? {
        get {
            return Keychain.data(for: key.rawValue)
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
            decode(Keychain.data(for: key.rawValue))
        }
        set {
            if let newValue = encode(newValue) {
                Keychain.set(newValue, for: key.rawValue, useSynchronization: sync)
            } else {
                Keychain.delete(key.rawValue)
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

//private extension Keychain {
//    static let secure = Keychain()
//}
