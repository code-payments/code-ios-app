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
    public static let mock  = ID(uuid: UUID(uuidString: "da777a11-bd88-4e04-9bf5-173fb4c137a6")!)
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
}

extension UUID {
    public enum Error: Swift.Error {
        case invalidSize
    }
}
