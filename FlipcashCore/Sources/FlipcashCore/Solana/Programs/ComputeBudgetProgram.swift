//
//  ComputeBudgetProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum ComputeBudgetProgram: CommandType {
    public typealias Definition = Command
}

extension ComputeBudgetProgram {
    public static let address = try! PublicKey(base58: "ComputeBudget111111111111111111111111111111")
}

extension ComputeBudgetProgram {
    public enum Command: Byte {
        case requestUnits = 0
        case requestHeapFrame = 1
        case setComputeUnitLimit = 2
        case setComputeUnitPrice = 3
    }
}
