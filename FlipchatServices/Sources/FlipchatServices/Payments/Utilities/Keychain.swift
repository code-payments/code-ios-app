//
//  Keychain.swift
//  Code
//
//  Created by Dima Bart on 2021-03-12.
//

import Foundation
import Security

@MainActor
public class Keychain {
    
    // MARK: - Init -
    
    public init() {}
    
    // MARK: - Setters -
    
    @discardableResult
    public func set(_ string: String, for key: String) -> Bool {
        set(Data(string.utf8), for: key)
    }
    
    @discardableResult
    public func set(_ data: Data, for key: String, useSynchronization: Bool = false) -> Bool {
        let query = Query(
            .service("Code (\(key))"),
            .account(key),
            .class(.genericPassword),
            .value(data),
            .isSynchronizable(useSynchronization ? .true : .false)
        )
        
        // Keychain will reject any insert queries for
        // duplicate items. We have to delete before
        // inserting any potential duplicates.
        delete(key)
        
        return addItem(query: query)
    }
    
    // MARK: - Getters -
    
    public func string(for key: String) -> String? {
        if let data = data(for: key) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    public func data(for key: String, migrateIfNeeded: Bool = true) -> Data? {
        let query = Query(
            .account(key),
            .matchLimit(.one),
            .class(.genericPassword),
            .isSynchronizable(.any),
            .shouldReturnData(true)
        )
        
        return copyMatching(query: query)
    }
    
    // MARK: - Delete -
    
    @discardableResult
    public func delete(_ key: String) -> Bool {
        let query = Query(
            .account(key),
            .class(.genericPassword),
            .isSynchronizable(.any)
        )
        
        return SecItemDelete(query.dictionary) == noErr
    }
    
    // MARK: - Security -
    
    private func copyMatching(query: Query) -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query.dictionary, &result)
        if status == errSecSuccess {
            print("[Keychain] Accessed: \(query.account ?? "nil"), accessGroup: \(query.accessGroup ?? "nil")")
            return result as? Data
        } else if status != errSecItemNotFound {
            if let error = SecCopyErrorMessageString(status, nil) {
                print("[Keychain] Fetch error: \(error as String)")
            }
        }
        
        return nil
    }
    
    private func addItem(query: Query) -> Bool {
        let status = SecItemAdd(query.dictionary, nil)
        if status != errSecSuccess {
            if let error = SecCopyErrorMessageString(status, nil) {
                print("[Keychain] Failed to save \(query.account ?? "nil"): (\(status)) \(error as String)")
            }
        }
        
        return status == errSecSuccess
    }
}

// MARK: - Query -

extension Keychain {
    struct Query {
        
        private var attributes: [Attribute]
        
        var dictionary: CFDictionary {
            Set(attributes).query as CFDictionary
        }
        
        var account: String? {
            for attribute in attributes {
                if case .account(let account) = attribute {
                    return account
                }
            }
            return nil
        }
        
        var accessGroup: String? {
            for attribute in attributes {
                if case .accessGroup(let group) = attribute {
                    return group
                }
            }
            return nil
        }
        
        init(_ attributes: Attribute...) {
            self.attributes = attributes
        }
        
        mutating func insert(_ attributes: Attribute...) {
            self.attributes.append(contentsOf: attributes)
        }
        
        mutating func remove(_ attribute: Attribute) {
            if let index = attributes.firstIndex(of: attribute) {
                attributes.remove(at: index)
            }
        }
    }
}

// MARK: - Attribute -

extension Keychain {
    enum Attribute: Hashable {
        
        case `class`(Class)
        case service(String)
        case account(String)
        case accessible(Accessible)
        case accessGroup(String)
        case accessControl(Accessible, SecAccessControlCreateFlags)
        case matchLimit(MatchLimit)
        case shouldReturnReferences(Bool)
        case shouldReturnAttributes(Bool)
        case shouldReturnData(Bool)
        case isSynchronizable(Ternary)
        case value(Data)
        
        var key: String {
            _key as String
        }
        
        private var _key: CFString {
            switch self {
            case .class:                          return kSecClass
            case .service:                        return kSecAttrService
            case .account:                        return kSecAttrAccount
            case .matchLimit:                     return kSecMatchLimit
            case .shouldReturnReferences:         return kSecReturnPersistentRef
            case .shouldReturnAttributes:         return kSecReturnAttributes
            case .shouldReturnData:               return kSecReturnData
            case .isSynchronizable:               return kSecAttrSynchronizable
            case .value:                          return kSecValueData
            case .accessible:                     return kSecAttrAccessible
            case .accessGroup:                    return kSecAttrAccessGroup
            case .accessControl:                  return kSecAttrAccessControl
            }
        }
        
        var value: Any? {
            switch self {
            case .class(let value):                          return value.rawValue
            case .service(let value):                        return value
            case .account(let value):                        return value
            case .matchLimit(let value):                     return value.rawValue
            case .shouldReturnReferences(let value):         return value.cfBool
            case .shouldReturnAttributes(let value):         return value.cfBool
            case .shouldReturnData(let value):               return value.cfBool
            case .isSynchronizable(let value):               return value.rawValue
            case .value(let value):                          return value
            case .accessible(let value):                     return value.rawValue
            case .accessGroup(let value):                    return value
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
