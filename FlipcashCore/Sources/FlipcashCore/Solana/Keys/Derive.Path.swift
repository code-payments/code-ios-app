//
//  Derive.Path.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Derive {
    public struct Path: Codable, Equatable, Hashable, Sendable {
        
        public let indexes: [Index]
        public let password: String?
        
        public var stringRepresentation: String {
            let components = indexes.map { $0.stringRepresentation }.joined(separator: Derive.Path.separator)
            return "\(Self.identifier)\(Self.separator)\(components)"
        }
        
        // MARK: - Init -
        
        public init?(_ string: String, password: String? = nil) {
            let strings = string.components(separatedBy: Self.separator)
            
            guard strings.first == Self.identifier else {
                return nil
            }
            
            let indexStrings = strings[1...]
            
            let indexes: [Index] = indexStrings.compactMap { string in
                if let index = string.firstIndex(of: "'"), let value = UInt32(string[..<index]) {
                    return Index(value: value, hardened: true)
                    
                } else if let value = UInt32(string) {
                    return Index(value: value, hardened: false)
                } else {
                    return nil
                }
            }
            
            guard indexes.count == indexStrings.count else {
                return nil
            }
            
            self.init(indexes: indexes, password: password)
        }
        
        internal init(indexes: [Index], password: String? = nil) {
            self.indexes = indexes
            self.password = password
        }
    }
}

// MARK: - CustomStringConvertible -

extension Derive.Path: CustomStringConvertible {
    public var description: String {
        stringRepresentation
    }
}

// MARK: - Constants -

extension Derive.Path {
    private static let identifier = "m"
    private static let separator = "/"
    private static let hardener = "'"
}

// MARK: - Index -

extension Derive.Path {
    public struct Index: Codable, Equatable, Hashable, Sendable {
        
        public var value: UInt32
        public var hardened: Bool
        
        var stringRepresentation: String {
            "\(value)\(hardened ? Derive.Path.hardener : "")"
        }
    }
}

// MARK: - Derivations -

extension Derive.Path {
    
    public static func primary() -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'")!
    }
    
    public static func relationship(domain: String) -> Derive.Path {
        Derive.Path("m/44'/501'/0'/0'/0'/0", password: domain)!
    }
}
