//
//  PublicKey+Definitions.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension PublicKey {
    public static let usdc          = try! PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
    public static let jeffy         = try! PublicKey(base58: "52MNGpgvydSwCtC2H4qeiZXZ1TxEuRVCRGa8LAfk2kSj")
    public static let farmerCoin    = try! PublicKey(base58: "2o4PFbDZ73BihFraknfVTQeUtELKAeVUL4oa6bkrYU3A")
    public static let knickNight    = try! PublicKey(base58: "497Wy6cY9BjWBiaDHzJ7TcUZqF2gE1Qm7yXtSj1vSr5W")
    public static let usdcAuthority = try! PublicKey(base58: "cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
}

extension PublicKey {
    public var mintDecimals: Int {
        if self == .usdc {
            return 6
        } else {
            return 10
        }
    }
}
