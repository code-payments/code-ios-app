//
//  ID.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct ID: Codable, Equatable, Hashable {
    
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
    public var uuid: UUID? {
        guard data.count == 16 else {
            return nil
        }
        
        return UUID(uuid: (
            data[0],  data[1],  data[2],  data[3],
            data[4],  data[5],  data[6],  data[7],
            data[8],  data[9],  data[10], data[11],
            data[12], data[13], data[14], data[15]
        ))
    }
}

extension ID: CustomStringConvertible {
    public var description: String {
        uuid?.uuidString ?? data.hexEncodedString()
    }
}

extension ID {
    public static let null = ID(data: Data([0x00]))
    
    public static var random: ID {
        ID(data: Data(UUID().uuidString.utf8))
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
