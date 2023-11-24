//
//  Keychain.swift
//  Code
//
//  Created by Dima Bart on 2021-03-12.
//

import Foundation
import Security
import LocalAuthentication

class Keychain {
    
    private let context = LAContext()
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Setters -
    
    @discardableResult
    func set(_ string: String, for key: String, useBiometrics: Bool = false) -> Bool {
        set(Data(string.utf8), for: key, useBiometrics: useBiometrics)
    }
    
    @discardableResult
    func set(_ data: Data, for key: String, useSynchronization: Bool = false, useBiometrics: Bool = false) -> Bool {
        var query = Query(
            .account(key),
            .class(.genericPassword),
            .value(data),
            .isSynchronizable(useSynchronization ? .true : .false)
        )
        
        if useBiometrics {
            query.insert(.accessControl(.whenPasscodeSetThisDeviceOnly, .userPresence))
        } else {
            query.insert(.accessible(.whenUnlocked))
        }
        
        // Keychain will reject any insert queries for
        // duplicate items. We have to delete before
        // inserting any potential duplicates.
        delete(for: key)

        let status = SecItemAdd(query.dictionary, nil)
        if status != errSecSuccess {
            if let error = SecCopyErrorMessageString(status, nil) {
                print("[Keychain] Failed to save \(key): (\(status)) \(error as String)")
            }
        }
        
        return status == errSecSuccess
    }
    
    // MARK: - Getters -
    
    func string(for key: String) -> String? {
        if let data = data(for: key) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func data(for key: String) -> Data? {
        let query = Query(
            .account(key),
            .matchLimit(.one),
            .class(.genericPassword),
            .isSynchronizable(.any),
            .shouldReturnData(true)
        )
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query.dictionary, &result)
        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            if let error = SecCopyErrorMessageString(status, nil) {
                print("[Keychain] Fetch error: \(error as String)")
            }
        }

        return nil
    }
    
    // MARK: - Delete -
    
    @discardableResult
    func delete(for key: String) -> Bool {
        let query = Query(
            .account(key),
            .class(.genericPassword),
            .isSynchronizable(.any)
        )
        
        return SecItemDelete(query.dictionary) == noErr
    }
}

// MARK: - Query -

extension Keychain {
    struct Query {
        
        private var attributes: [Attribute]
        
        var dictionary: CFDictionary {
            Set(attributes).query as CFDictionary
        }
        
        init(_ attributes: Attribute...) {
            self.attributes = attributes
        }
        
        mutating func insert(_ attributes: Attribute...) {
            self.attributes.append(contentsOf: attributes)
        }
    }
}

// MARK: - Attribute -

extension Keychain {
    enum Attribute: Hashable {
        
        case `class`(Class)
        case account(String)
        case accessible(Accessible)
        case accessControl(Accessible, SecAccessControlCreateFlags)
        case matchLimit(MatchLimit)
        case shouldReturnReferences(Bool)
        case shouldReturnAttributes(Bool)
        case shouldReturnData(Bool)
        case shouldUseAuthenticationContext(LAContext)
        case isSynchronizable(Ternary)
        case value(Data)
        
        var key: String {
            _key as String
        }
        
        private var _key: CFString {
            switch self {
            case .class:                          return kSecClass
            case .account:                        return kSecAttrAccount
            case .matchLimit:                     return kSecMatchLimit
            case .shouldReturnReferences:         return kSecReturnPersistentRef
            case .shouldReturnAttributes:         return kSecReturnAttributes
            case .shouldReturnData:               return kSecReturnData
            case .shouldUseAuthenticationContext: return kSecUseAuthenticationContext
            case .isSynchronizable:               return kSecAttrSynchronizable
            case .value:                          return kSecValueData
            case .accessible:                     return kSecAttrAccessible
            case .accessControl:                  return kSecAttrAccessControl
            }
        }
        
        var value: Any? {
            switch self {
            case .class(let value):                          return value.rawValue
            case .account(let value):                        return value
            case .matchLimit(let value):                     return value.rawValue
            case .shouldReturnReferences(let value):         return value.cfBool
            case .shouldReturnAttributes(let value):         return value.cfBool
            case .shouldReturnData(let value):               return value.cfBool
            case .shouldUseAuthenticationContext(let value): return value
            case .isSynchronizable(let value):               return value.rawValue
            case .value(let value):                          return value
            case .accessible(let value):                     return value.rawValue
            case .accessControl(let accessible, let flags):
                return SecAccessControlCreateWithFlags(nil, accessible.rawValue, flags, nil)!
            }
        }
    }
}

// MARK: - Accessible -

extension Keychain {
    enum Accessible: Hashable {
        
        case whenUnlocked
        case whenPasscodeSetThisDeviceOnly
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlock
        case afterFirstUnlockThisDeviceOnly
        
        var rawValue: CFString {
            switch self {
            case .whenUnlocked:                   return kSecAttrAccessibleWhenUnlocked
            case .whenPasscodeSetThisDeviceOnly:  return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            case .whenUnlockedThisDeviceOnly:     return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlock:               return kSecAttrAccessibleAfterFirstUnlock
            case .afterFirstUnlockThisDeviceOnly: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }
}

// MARK: - Match Limit -

extension Keychain.Attribute {
    enum MatchLimit: Hashable {
        
        case one
        case all
        
        var rawValue: CFString {
            switch self {
            case .one: return kSecMatchLimitOne
            case .all: return kSecMatchLimitAll
            }
        }
    }
}

// MARK: - Class -

extension Keychain.Attribute {
    enum Class: Hashable {
        
        case internetPassword
        case genericPassword
        case certificate
        case key
        case identity
        
        var rawValue: CFString {
            switch self {
            case .internetPassword: return kSecClassInternetPassword
            case .genericPassword:  return kSecClassGenericPassword
            case .certificate:      return kSecClassCertificate
            case .key:              return kSecClassKey
            case .identity:         return kSecClassIdentity
            }
        }
    }
}

// MARK: - Ternary -

extension Keychain.Attribute {
    enum Ternary {
        
        case `true`
        case `false`
        case any
        
        var rawValue: Any {
            switch self {
            case .true:  return true.cfBool
            case .false: return false.cfBool
            case .any:   return kSecAttrSynchronizableAny
            }
        }
    }
}

extension SecAccessControlCreateFlags: Hashable {}

private extension Set where Element == Keychain.Attribute {
    var query: [String: Any] {
        var query: [String: Any] = [:]
        forEach {
            if let value = $0.value {
                query[$0.key] = value
            }
        }
        return query
    }
}

private extension Bool {
    var cfBool: CFBoolean {
        if self {
            return kCFBooleanTrue
        } else {
            return kCFBooleanFalse
        }
    }
}
