//
//  InstructionType.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public protocol ProgramType {
    static var address: PublicKey { get }
}

public protocol CommandType: ProgramType {
    associatedtype Definition: RawRepresentable
}

public protocol InstructionType {
    init(instruction: Instruction) throws
    func instruction() -> Instruction
    func encode() -> Data
}

extension CommandType where Definition.RawValue: FixedWidthInteger {
    private static var commandByteLength: Int {
        MemoryLayout<Definition.RawValue>.stride
    }
    
    public static func ensure(_ instruction: Instruction, is command: Definition) throws {
        let stride = commandByteLength
        guard instruction.data.count >= stride else {
            throw CommandParseError.commandNotFound
        }
        
        var bytes = [Byte](repeating: 0, count: stride)
        bytes.withUnsafeMutableBytes {
            $0.copyBytes(from: instruction.data.prefix(stride))
        }
        
        guard
            let value = Definition.RawValue(bytes: bytes),
            let parsedCommand = Definition(rawValue: value),
            parsedCommand == command
        else {
            throw CommandParseError.payloadNotFound
        }
    }
    
    @discardableResult
    public static func parse(_ command: Definition? = nil, instruction: Instruction, expectingAccounts: Int) throws -> Data {
        guard instruction.program == Self.address else {
            throw CommandParseError.instructionMismatch
        }
        
        if let command = command {
            try ensure(instruction, is: command)
        }
        
        guard instruction.accounts.count == expectingAccounts else {
            throw CommandParseError.accountMismatch
        }
        
        var data = instruction.data
        
        // Consume the command type into the void
        _ = data.consume(commandByteLength)
        
        return data
    }
}

public enum CommandParseError: Swift.Error {
    case instructionMismatch
    case commandNotFound
    case payloadNotFound
    case accountMismatch
}
