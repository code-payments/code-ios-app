//
//  TokenProgram.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum TokenProgram: CommandType {
    public typealias Definition = Command
}

extension TokenProgram {
    public static let address = PublicKey(base58: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")! // Mainnet
}

extension TokenProgram {
    public enum Command: Byte {
        case initializeMint
        case initializeAccount
        case initializeMultisig
        case transfer
        case approve
        case revoke
        case setAuthority
        case mintTo
        case burn
        case closeAccount
        case freezeAccount
        case thawAccount
        case transfer2
        case approve2
        case mintTo2
        case burn2
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
