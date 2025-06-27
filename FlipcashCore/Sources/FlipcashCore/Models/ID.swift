//
//  ID.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public typealias UserID = UUID

public struct ID: Codable, Equatable, Hashable, Sendable {
    
    public let data: Data
    
    public init(data: Data) {
        self.data = data
    }
}

extension ID {
    
    public init(uuid: UUID) {
        let n = uuid.uuid
        let d = Data([
            n.0, n.1, n.2,  n.3,  n.4,  n.5,  n.6,  n.7,
            n.8, n.9, n.10, n.11, n.12, n.13, n.14, n.15,
        ])
        
        self.init(data: d)
    }
    
    public init?(uuid: UUID?) {
        if let uuid {
            self.init(uuid: uuid)
        } else {
            return nil
        }
    }
    
    public var uuid: UUID {
        guard data.count == 16 else {
            fatalError("ID is not 16 bytes, instead \(data.count) bytes were provided.")
        }
        
        return UUID(uuid: (
            data[0],  data[1],  data[2],  data[3],
            data[4],  data[5],  data[6],  data[7],
            data[8],  data[9],  data[10], data[11],
            data[12], data[13], data[14], data[15]
        ))
    }
}

extension ID: Comparable {
    public static func < (lhs: ID, rhs: ID) -> Bool {
        lhs.data.lexicographicallyPrecedes(rhs.data)
    }
}

extension ID: CustomStringConvertible {
    public var description: String {
        data.hexString()
    }
}

extension ID {
    public static let null = ID(data: Data([0x00]))
    
    public static var random: ID {
        ID(data: UUID().data)
    }
}

extension ID {
    public static let mock  = ID(uuid: UUID(uuidString: "da777a11-bd88-4e04-9bf5-173fb4c137a6")!)
    public static let mock1 = ID(uuid: UUID(uuidString: "950dfabd-0acb-49e8-8a5a-710528002eef")!)
    public static let mock2 = ID(uuid: UUID(uuidString: "85717b5a-d5be-4feb-ad50-648e22310e64")!)
    public static let mock3 = ID(uuid: UUID(uuidString: "79e6b0e0-a3c2-446b-9e27-f1fba24caa00")!)
    public static let mock4 = ID(uuid: UUID(uuidString: "5e63c1c6-bed0-4a6e-99f5-1d41adc39e19")!)
    public static let mock5 = ID(uuid: UUID(uuidString: "ac9c3690-5e81-43e7-9d53-bce17f2a5acd")!)
    public static let mock6 = ID(uuid: UUID(uuidString: "0b66c9ca-6215-4bec-bbbf-f2b48682a423")!)
    public static let mock7 = ID(uuid: UUID(uuidString: "ce97fa8f-c005-4134-91ac-40937096bbf3")!)
}

// MARK: - UUID -

extension UUID {
    
    public init(data: Data) throws {
        guard data.count == 16 else {
            throw Error.invalidSize
        }
        
        self.init(uuid: (
            data[0],  data[1],  data[2],  data[3],
            data[4],  data[5],  data[6],  data[7],
            data[8],  data[9],  data[10], data[11],
            data[12], data[13], data[14], data[15]
        ))
    }
    
    public var bytes: [Byte] {
        let n = uuid
        return [
            n.0, n.1, n.2,  n.3,  n.4,  n.5,  n.6,  n.7,
            n.8, n.9, n.10, n.11, n.12, n.13, n.14, n.15,
        ]
    }
    
    public var data: Data {
        Data(bytes)
    }
    
    public func generateBlockchainMemo() -> String {
        let type:    Byte = 1
        let version: Byte = 0
        let flags: UInt32 = 0
        
        var data = Data()
        
        data.append(contentsOf: type.bytes)
        data.append(contentsOf: version.bytes)
        data.append(contentsOf: flags.bytes)
        
        data.append(self.data)
        
        return Base58.fromBytes(data.bytes)
    }
}

extension UUID {
    public enum Error: Swift.Error {
        case invalidSize
    }
}
