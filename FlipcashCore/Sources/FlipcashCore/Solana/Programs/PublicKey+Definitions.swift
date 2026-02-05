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
    public static let usdc          = try! PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
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
