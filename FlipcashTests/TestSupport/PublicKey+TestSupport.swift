//
//  PublicKey+TestSupport.swift
//  Code
//
//  Created by Raul Riera on 2026-02-06.
//

import FlipcashCore

extension PublicKey {
    static let jeffy = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")

    /// Deterministic 32-byte mint key parameterized by `index`. Used by stress
    /// tests that need many distinguishable mints without colliding on a real
    /// fixture. Encodes `index` across the trailing 4 bytes (little-endian) so
    /// callers can pass values up to `UInt32.max` without overflow.
    static func testMint(index: Int) -> PublicKey {
        var bytes = [Byte](repeating: 0, count: 32)
        let value = UInt32(truncatingIfNeeded: index)
        bytes[28] = Byte(truncatingIfNeeded: value)
        bytes[29] = Byte(truncatingIfNeeded: value >> 8)
        bytes[30] = Byte(truncatingIfNeeded: value >> 16)
        bytes[31] = Byte(truncatingIfNeeded: value >> 24)
        return try! PublicKey(bytes)
    }
}
