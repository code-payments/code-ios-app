//
//  Key.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public typealias Byte = UInt8

public protocol KeyType {
    
    static var length: Int { get }
    
    var bytes: [Byte] { get }
    
    init?(_ bytes: [Byte])
}

// MARK: - Data -

extension KeyType {
    
    public static var zero: Self {
        self.init([Byte].zeroed(with: Self.length))!
    }
    
    public init?(_ data: Data) {
        self.init(data.bytes)
    }
    
    public var data: Data {
        bytes.data
    }
}

// MARK: - Base58 -

extension KeyType {
    
    public var base58: String {
        Base58.fromBytes(bytes)
    }
    
    public init?(base58: String) {
        self.init(Base58.toBytes(base58))
    }
}

// MARK: - Key16 -

public struct Key16: KeyType, Equatable, Codable, Hashable {
    
    public static let length = 16
    
    public let bytes: [Byte]
    
    public init?(_ bytes: [Byte]) {
        guard bytes.count == Self.length else {
            return nil
        }

        self.bytes = bytes
    }
}

extension Key16: CustomStringConvertible {
    public var description: String {
        base58
    }
}

// MARK: - Key32 -

public struct Key32: KeyType, Equatable, Codable, Hashable {
    
    public static let length = 32
    
    public let bytes: [Byte]
    
    public init?(_ bytes: [Byte]) {
        guard bytes.count == Self.length else {
            return nil
        }

        self.bytes = bytes
    }
}

extension Key32: CustomStringConvertible {
    public var description: String {
        base58
    }
}

extension Key32: Identifiable {
    public var id: String {
        base58
    }
}

// MARK: - Key64 -

public struct Key64: KeyType, Equatable, Codable, Hashable {
    
    public static let length = 64
    
    public let bytes: [Byte]

    public init?(_ bytes: [Byte]) {
        guard bytes.count == Self.length else {
            return nil
        }

        self.bytes = bytes
    }
}

extension Key64: CustomStringConvertible {
    public var description: String {
        base58
    }
}

extension Key64: Identifiable {
    public var id: String {
        base58
    }
}
