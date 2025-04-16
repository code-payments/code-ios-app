//
//  SystemProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum SystemProgram: CommandType {
    public typealias Definition = Command
}

extension SystemProgram {
    public static let address = PublicKey.zero // Mainnet
}

extension SystemProgram {
    public enum Command: UInt32 {
        case createAccount
        case assign
        case transfer
        case createAccountWithSeed
        case advanceNonceAccount
        case withdrawNonceAccount
        case initializeNonceAccount
        case authorizeNonceAccount
        case allocate
        case allocateWithSeed
        case assignWithSeed
        case transferWithSeed
    }
}
