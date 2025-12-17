//
//  MemoProgram.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation

public enum MemoProgram: CommandType {
    public typealias Definition = Command
}

extension MemoProgram {
    public static let address = try! PublicKey(base58: "Memo1UhkJRfHyvLMcVucJwxXeuD728EqVDDwQDxFMNo")
}

extension MemoProgram {
    public enum Command: Byte {
        case memo = 0
    }
}
