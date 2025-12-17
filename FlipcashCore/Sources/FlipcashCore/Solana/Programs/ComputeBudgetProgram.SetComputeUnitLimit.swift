//
//  ComputeBudgetProgram.SetComputeUnitLimit.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension ComputeBudgetProgram {
    
    ///   Set a specific transaction-wide program compute unit limit.
    ///
    ///   No accounts required
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana/blob/master/sdk/program/src/compute_budget.rs
    ///
    public struct SetComputeUnitLimit: Equatable, Hashable, Codable {
        
        public let units: UInt32
        
        public init(units: UInt32) {
            self.units = units
        }
    }
}

// MARK: - InstructionType -

extension ComputeBudgetProgram.SetComputeUnitLimit: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try ComputeBudgetProgram.parse(.setComputeUnitLimit, instruction: instruction, expectingAccounts: 0)
        
        guard data.count >= 4 else {
            throw CommandParseError.payloadNotFound
        }
        
        self.init(
            units: UInt32(bytes: Array(data.prefix(4)))!
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
        
        data.append(contentsOf: ComputeBudgetProgram.Command.setComputeUnitLimit.rawValue.bytes)
        data.append(contentsOf: units.bytes)
        
        return data
    }
}
