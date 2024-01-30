//
//  ComputeBudgetProgram.SetComputeUnitLimit.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension ComputeBudgetProgram {
    public struct SetComputeUnitLimit: Equatable, Hashable, Codable {
        
        public let limit: UInt32
        
        public init(limit: UInt32) {
            self.limit = limit
        }
    }
}

// MARK: - InstructionType -

extension ComputeBudgetProgram.SetComputeUnitLimit: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data   = try ComputeBudgetProgram.parse(.setComputeUnitLimit, instruction: instruction, expectingAccounts: 0)
        let stride = MemoryLayout<UInt32>.stride
        
        guard data.canConsume(stride), let limit = UInt32(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(limit: limit)
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: SystemProgram.address,
            accounts: [],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: ComputeBudgetProgram.Command.setComputeUnitLimit.rawValue.bytes)
        data.append(contentsOf: limit.bytes)
        
        return data
    }
}
