//
//  TimelockProgram.swift
//  FlipcashCore
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum VMProgram: CommandType {
    public typealias Definition = Command
}

extension VMProgram {
    public static let address = try! PublicKey(base58: "vmZ1WUq8SxjBWcaeTCvgJRZbS84R61uniFsQy5YMRTJ")
}

extension VMProgram {
    public enum Command: UInt8 {
        case unknown = 0
        case transferForSwap = 17
        case closeSwapAccountIfEmpty = 19
    }
}

