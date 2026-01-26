//
//  UsdfProgram.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-26.
//

import Foundation

public enum UsdfProgram {
    public static let address = try! PublicKey(base58: "usdfcP2V1bh1Lz7Y87pxR4zJd3wnVtssJ6GeSHFeZeu")

    public enum Command: UInt8 {
        // initialize = 1
        case swap = 2
        case transfer = 3
    }
}
