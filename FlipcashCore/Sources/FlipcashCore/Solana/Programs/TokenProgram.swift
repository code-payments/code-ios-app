//
//  TokenProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum TokenProgram: CommandType {
    public typealias Definition = Command
}

extension TokenProgram {
    public static let address = try! PublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") // Mainnet
}

extension TokenProgram {
    public enum Command: Byte {
        case initializeMint = 0
        case initializeAccount = 1
        case initializeMultisig = 2
        case transfer = 3
        case approve = 4
        case revoke = 5
        case setAuthority = 6
        case mintTo = 7
        case burn = 8
        case closeAccount = 9
        case freezeAccount = 10
        case thawAccount = 11
        case transferChecked = 12
        case approveChecked = 13
        case mintToChecked = 14
        case burnChecked = 15
        case initializeAccount2 = 16
        case syncNative = 17
        case initializeAccount3 = 18
        case initializeMultisig2 = 19
        case initializeMint2 = 20
    }
}


extension TokenProgram {
    public enum AuthorityType: Byte, Equatable, Hashable, Codable {
        case mintTokens
        case freezeAccount
        case accountHolder
        case closeAccount
    }
}
