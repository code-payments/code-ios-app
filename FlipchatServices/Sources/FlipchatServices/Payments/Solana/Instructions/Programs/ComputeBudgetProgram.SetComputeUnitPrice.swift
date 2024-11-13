//
//  ComputeBudgetProgram.SetComputeUnitPrice.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension ComputeBudgetProgram {
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
        var data   = try ComputeBudgetProgram.parse(.setComputeUnitPrice, instruction: instruction, expectingAccounts: 0)
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let microLamports = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(microLamports: microLamports)
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
