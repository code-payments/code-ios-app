//
//  AddressLookupTable.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation
import FlipcashAPI

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
        var data = Data()
        
        data.append(publicKey.data)
        data.append(ShortVec.encodeLength(UInt16(writableIndexes.count)))
        data.append(contentsOf: writableIndexes)
        data.append(ShortVec.encodeLength(UInt16(readonlyIndexes.count)))
        data.append(contentsOf: readonlyIndexes)
        
        return data
    }
}

extension AddressLookupTable {
    public init?(_ proto: Code_Common_V1_SolanaAddressLookupTable) {
        guard
            let entries = try? proto.entries.map({ id in
                try PublicKey(id.value)
            }),
            let address = try? PublicKey(proto.address.value)
        else {
            return nil
        }
    
        self.init(publicKey: address, addresses: entries)
    }
    
    public var proto: Code_Common_V1_SolanaAddressLookupTable {
        .with {
            $0.address = publicKey.solanaAccountID
            $0.entries = addresses.map { $0.solanaAccountID }
        }
    }
}
