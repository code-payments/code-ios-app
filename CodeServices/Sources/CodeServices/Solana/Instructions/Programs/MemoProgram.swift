//
//  MemoProgram.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum MemoProgram: CommandType {
    public typealias Definition = Command
}

extension MemoProgram {
    public static let address = PublicKey(base58: "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo")! // Mainnet
}

extension MemoProgram {
    public enum Command: Byte {
        case unknown
    }
}
