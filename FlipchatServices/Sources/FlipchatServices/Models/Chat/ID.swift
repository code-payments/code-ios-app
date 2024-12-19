//
//  ID.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public typealias Cursor = ID
public typealias ChatID = ID
public typealias UserID = ID
public typealias MessageID = ID

public struct ID: Codable, Equatable, Hashable, Sendable {
    
    public let data: Data
    
    public init(data: Data) {
        self.data = data
    }
}

extension ID {
    enum Error: Swift.Error {
        case invalidData
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
        uuid.uuidString
    }
}

extension ID {
    public static let null = ID(data: Data([0x00]))
    
    public static var random: ID {
        ID(data: UUID().data)
    }
}

extension ID {
    public static let mock  = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFF]))
    public static let mock1 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFE]))
    public static let mock2 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFD]))
    public static let mock3 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFC]))
    public static let mock4 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFB]))
    public static let mock5 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xFA]))
    public static let mock6 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xF0]))
    public static let mock7 = ID(data: Data([0xFF, 0xFF, 0xFF, 0xF1]))
}
