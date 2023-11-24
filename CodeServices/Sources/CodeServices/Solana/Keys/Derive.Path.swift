//
//  Derive.Path.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension Derive {
    public struct Path: Codable, Equatable, Hashable {
        
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
    public struct Index: Codable, Equatable, Hashable {
        
        public var value: UInt32
        public var hardened: Bool
        
        var stringRepresentation: String {
            "\(value)\(hardened ? Derive.Path.hardener : "")"
        }
    }
}
