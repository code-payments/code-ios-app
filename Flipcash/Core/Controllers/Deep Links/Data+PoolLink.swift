//
//  Data+PoolLink.swift
//  Code
//
//  Created by Dima Bart on 2025-07-07.
//

import Foundation

extension Data {
    static func parseBase64EncodedPoolInfo(_ string: String) throws -> PoolInfo {
        let data = Data(base64Encoded: string)!
        let info = try JSONDecoder().decode(PoolInfo.self, from: data)
        return info
    }
    
    static func base64EncodedPoolInfo(_ info: PoolInfo) throws -> String {
        try JSONEncoder().encode(info)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

struct PoolInfo: Codable {
    let name: String
    let amount: String
    let yesCount: Int
    let noCount: Int
    
    enum CodingKeys: String, CodingKey {
        case name     = "p"
        case amount   = "a"
        case yesCount = "y"
        case noCount  = "n"
    }
}
