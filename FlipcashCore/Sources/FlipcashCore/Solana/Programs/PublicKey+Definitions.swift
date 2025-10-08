//
//  PublicKey+Definitions.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension PublicKey {
    
//    public static let kinMint       = PublicKey(base58: "kinXdEcpDQeHPEuQnqmUgtYykqKGVFq6CeVX5iAHJq6")!
//
//    public static let subsidizer    = PublicKey(base58: "codeHy87wGD5oMRLG75qKqsSi1vWE3oxNyYmXo5F9YR")!
    
    public static let timeAuthority = try! PublicKey(base58: "cash11ndAmdKFEnG2wrQQ5Zqvr1kN9htxxLyoPLYFUV")
}

extension PublicKey {
    public static let kin  = try! PublicKey(base58: "kinXdEcpDQeHPEuQnqmUgtYykqKGVFq6CeVX5iAHJq6")
    public static let usdc = try! PublicKey(base58: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")
}
