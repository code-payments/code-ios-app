//
//  AssociatedTokenProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum AssociatedTokenProgram: CommandType {
    public typealias Definition = Command
}

extension AssociatedTokenProgram {
    public static let address = PublicKey(base58: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")! // Mainnet
}

extension AssociatedTokenProgram {
    public enum Command: Byte {
        case unknown
    }
}
