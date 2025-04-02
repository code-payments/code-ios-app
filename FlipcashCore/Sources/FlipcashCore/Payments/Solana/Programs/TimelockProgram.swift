//
//  TimelockProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum TimelockProgram: CommandType {
    public typealias Definition = Command
}

extension TimelockProgram {
    public static let address = PublicKey(base58: "time2Z2SCnn3qYg3ULKVtdkh8YmZ5jFdKicnA1W2YnJ")! // Mainnet
}

extension TimelockProgram {
    public enum Command: UInt64 {
        case initialize               = 0xED9B980D1F6DAFAF
        case activate                 = 0x52AA37976423CBC2
        case transferWithAuthority    = 0xA5474581C0DE8044
        case revokeLockWithAuthority  = 0x90C908ABF23AB5E5
        case deactivateLock           = 0x0D8E1C71AC21702C
        case withdraw                 = 0x22A16D949C4612B7
        case closeAccounts            = 0x01CAFA22E95EDEAB
        case burnDustWithAuthority    = 0x2D4E7C0EDAFF2A27
    }
}
