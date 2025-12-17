//
//  ComputeBudgetProgram.SetComputeUnitPrice.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension ComputeBudgetProgram {
    
    ///   Set a compute unit price in "micro-lamports" to pay a higher transaction fee for higher transaction prioritization.
    ///
    ///   No accounts required
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana/blob/master/sdk/program/src/compute_budget.rs
    ///
    public struct SetComputeUnitPrice: Equatable, Hashable, Codable {
        
        public let microLamports: UInt64
        
        public init(microLamports: UInt64) {
            self.microLamports = microLamports
        }
    }
}

// MARK: - InstructionType -

extension ComputeBudgetProgram.SetComputeUnitPrice: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try ComputeBudgetProgram.parse(.setComputeUnitPrice, instruction: instruction, expectingAccounts: 0)
        
        guard data.count >= 8 else {
            throw CommandParseError.payloadNotFound
        }
        
        self.init(
            microLamports: UInt64(bytes: Array(data.prefix(8)))!
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: ComputeBudgetProgram.address,
            accounts: [],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: ComputeBudgetProgram.Command.setComputeUnitPrice.rawValue.bytes)
        data.append(contentsOf: microLamports.bytes)
        
        return data
    }
}
