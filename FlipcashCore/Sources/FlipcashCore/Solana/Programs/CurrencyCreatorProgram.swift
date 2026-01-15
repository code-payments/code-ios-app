//
//  CurrencyCreatorProgram.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

public enum CurrencyCreatorProgram: CommandType {
    public typealias Definition = Command
}

extension CurrencyCreatorProgram {
    public static let address = try! PublicKey(base58: "ccJYP5gjZqcEHaphcxAZvkxCrnTVfYMjyhSYkpQtf8Z")
}

extension CurrencyCreatorProgram {
    public enum Command: UInt8 {
        case unknown = 0
        case buyTokens = 4
        case sellTokens = 5
        case buyAndDepositIntoVm = 6
        case sellAndDepositIntoVm = 7
    }
}
