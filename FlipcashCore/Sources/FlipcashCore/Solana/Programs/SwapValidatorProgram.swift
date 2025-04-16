//
//  SwapValidatorProgram.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum SwapValidatorProgram: CommandType {
    public typealias Definition = Command
}

extension SwapValidatorProgram {
    public static let address = PublicKey(base58: "sWvA66HNNvgamibZe88v3NN5nQwE8tp3KitfViFjukA")!
}

extension SwapValidatorProgram {
    public enum Command: UInt64 {
        case preSwap  = 0x717F49CF8AC7DDB7
        case postSwap = 0xA1758AB339B7D59F
    }
}
