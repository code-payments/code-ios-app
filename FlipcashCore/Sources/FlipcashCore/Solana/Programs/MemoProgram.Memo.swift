//
//  MemoProgram.Memo.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension MemoProgram {
    
    ///   Add a memo to the transaction log.
    ///
    ///   No accounts required, memo is stored in instruction data.
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/master/memo/program/src/lib.rs
    ///
    public struct Memo: Equatable, Hashable, Codable {
        
        public let message: String
        
        public init(message: String) {
            self.message = message
        }
    }
}

// MARK: - InstructionType -

extension MemoProgram.Memo: InstructionType {
    
    public init(instruction: Instruction) throws {
        guard instruction.program == MemoProgram.address else {
            throw CommandParseError.instructionMismatch
        }
        
        guard let message = String(data: instruction.data, encoding: .utf8) else {
            throw CommandParseError.payloadNotFound
        }
        
        self.init(message: message)
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: MemoProgram.address,
            accounts: [],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        Data(message.utf8)
    }
}
