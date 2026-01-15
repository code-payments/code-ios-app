//
//  PublicKey+Definitions.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension PublicKey {
    public static let usdf          = try! PublicKey(base58: "5AMAA9JV9H97YYVxx8F6FsCMmTwXSuTTQneiup4RYAUQ")
    public static let jeffy         = try! PublicKey(base58: "54ggcQ23uen5b9QXMAns99MQNTKn7iyzq4wvCW6e8r25")
    public static let farmerCoin    = try! PublicKey(base58: "2o4PFbDZ73BihFraknfVTQeUtELKAeVUL4oa6bkrYU3A")
    public static let knickNight    = try! PublicKey(base58: "497Wy6cY9BjWBiaDHzJ7TcUZqF2gE1Qm7yXtSj1vSr5W")
    public static let usdcAuthority = try! PublicKey(base58: "cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
}

extension PublicKey {
    public var mintDecimals: Int {
        if self == .usdf {
            return 6
        } else {
            return 10
        }
    }
}
