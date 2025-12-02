//
//  AddressLookupTable.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation

public struct AddressLookupTable: Equatable, Hashable, Sendable {
    public let publicKey: PublicKey
    public let addresses: [PublicKey]
    
    public init(publicKey: PublicKey, addresses: [PublicKey]) {
        self.publicKey = publicKey
        self.addresses = addresses
    }
}

public struct MessageAddressTableLookup: Equatable, Sendable {
    public let publicKey: PublicKey
    public var writableIndexes: [UInt8]
    public var readonlyIndexes: [UInt8]
    
    public var description: String {
        "Lookup(publicKey: \(publicKey.base58), writable: \(writableIndexes), readonly: \(readonlyIndexes))"
    }
    
    public init(publicKey: PublicKey, writableIndexes: [UInt8], readonlyIndexes: [UInt8]) {
        self.publicKey = publicKey
        self.writableIndexes = writableIndexes
        self.readonlyIndexes = readonlyIndexes
    }
}

extension MessageAddressTableLookup {
    public func encode() -> Data {
        var data = self.publicKey.data
                
        let writableLength: UInt8 = UInt8(self.writableIndexes.count)
        data.append(Data([writableLength]))
        for index in self.writableIndexes {
            data.append(Data([index]))
        }
        
        let readonlyLength: UInt8 = UInt8(self.readonlyIndexes.count)
        data.append(Data([readonlyLength]))
        for index in self.readonlyIndexes {
            data.append(Data([index]))
        }
        
        return data
    }
}
