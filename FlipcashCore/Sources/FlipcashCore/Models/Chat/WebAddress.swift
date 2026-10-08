//
//  WebAddress.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Network

extension WebLinks {

    /// Whether a link preview may connect to `address`, per the fixture's `addresses` table;
    /// an IPv4-mapped IPv6 address is judged by its IPv4 part.
    public nonisolated static func isPublic(_ address: IPAddress) -> Bool {
        if let v6 = address as? IPv6Address {
            let b = [UInt8](v6.rawValue)
            if b[..<12].allSatisfy({ $0 == 0 }) { return false }                   // ::/96, incl. :: and ::1
            if b[..<12] == [0, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0] {        // 64:ff9b::/96 (NAT64)
                return isPublic(v4: Array(b[12...]))
            }
            if b[0] == 0x20 && b[1] == 0x02 { return false }                       // 2002::/16 (6to4)
            if let v4 = v6.asIPv4 { return isPublic(v4) }
            if b[0] & 0xFE == 0xFC { return false }                                // fc00::/7
            if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return false }                // fe80::/10
            if b[0] == 0xFE && b[1] & 0xC0 == 0xC0 { return false }                // fec0::/10
            return b[0] != 0xFF                                                    // ff00::/8
        }
        return isPublic(v4: [UInt8](address.rawValue))
    }

    private nonisolated static func isPublic(v4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (100, let x) where x & 0xC0 == 64: return false                       // 100.64/10
        case (172, let x) where x & 0xF0 == 16: return false                       // 172.16/12
        case (192, 0) where b[2] == 0 || b[2] == 2: return false                   // 192.0.0/24, 192.0.2/24
        case (198, 18...19): return false                                          // 198.18/15
        case (224...255, _): return false                                          // multicast, 240/4, broadcast
        default: return true
        }
    }
}
