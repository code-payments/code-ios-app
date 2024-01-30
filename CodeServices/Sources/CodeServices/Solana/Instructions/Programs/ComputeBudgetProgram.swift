//
//  ComputeBudgetProgram.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum ComputeBudgetProgram: CommandType {
    public typealias Definition = Command
}

extension ComputeBudgetProgram {
    public static let address = PublicKey(base58: "ComputeBudget111111111111111111111111111111")!
}

extension ComputeBudgetProgram {
    public enum Command: Byte {
        case requestUnits
        case requestHeapFrame
        case setComputeUnitLimit
        case setComputeUnitPrice
    }
}
