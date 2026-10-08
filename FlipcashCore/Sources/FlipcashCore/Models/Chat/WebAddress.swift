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
            if let v4 = v6.asIPv4 { return isPublic(v4) }
            let b = [UInt8](v6.rawValue)
            if b.allSatisfy({ $0 == 0 }) { return false }                          // ::
            if b.dropLast().allSatisfy({ $0 == 0 }) && b[15] == 1 { return false } // ::1
            if b[0] & 0xFE == 0xFC { return false }                                // fc00::/7
            if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return false }                // fe80::/10
            if b[0] == 0xFE && b[1] & 0xC0 == 0xC0 { return false }                // fec0::/10
            return b[0] != 0xFF                                                    // ff00::/8
        }
        let b = [UInt8](address.rawValue)
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (100, let x) where x & 0xC0 == 64: return false                       // 100.64/10
        case (172, let x) where x & 0xF0 == 16: return false                       // 172.16/12
        case (224...239, _): return false                                          // multicast
        case (255, 255) where b[2] == 255 && b[3] == 255: return false             // broadcast
        default: return true
        }
    }
}
