//
//  Instruction.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public struct Instruction: Equatable, Sendable {
    
    public var program: PublicKey
    public var accounts: [AccountMeta]
    public var data: Data
    
    public init(program: PublicKey, accounts: [AccountMeta], data: Data) {
        self.program = program
        self.accounts = accounts
        self.data = data
    }
    
    public func compile(using messageAccounts: [PublicKey]) -> CompiledInstruction {
        let programIndex = messageAccounts.firstIndex { $0 == program }!
        let accountIndexes = accounts.map { account in
            messageAccounts.firstIndex { $0 == account.publicKey }!
        }
        
        return CompiledInstruction(
            programIndex: programIndex,
            accountIndexes: accountIndexes,
            data: data
        )
    }
}

// MARK: - CompiledInstruction -

public struct CompiledInstruction: Equatable, Sendable {
    
    public var programIndex: Byte
    public var accountIndexes: [Byte]
    public var data: Data
    
    public var byteLength: Int {
        return
            1 +
            ShortVec.encodeLength(UInt16(accountIndexes.count)).count +
            accountIndexes.count +
            ShortVec.encodeLength(UInt16(data.count)).count +
            data.count
    }
    
    public init(programIndex: Int, accountIndexes: [Int], data: Data) {
        self.init(
            programIndex: Byte(programIndex),
            accountIndexes: accountIndexes.map { Byte($0) },
            data: data
        )
    }
    
    public init(programIndex: Byte, accountIndexes: [Byte], data: Data) {
        self.programIndex = Byte(programIndex)
        self.accountIndexes = accountIndexes.map { Byte($0) }
        self.data = data
    }
    
    public func decompile(using accounts: [AccountMeta]) -> Instruction? {
        // Validate programIndex is within bounds
        guard Int(programIndex) < accounts.count else {
            return nil
        }
        
        // Validate all accountIndexes are within bounds
        guard accountIndexes.allSatisfy({ Int($0) < accounts.count }) else {
            return nil
        }
        
        let program = accounts[Int(programIndex)].publicKey
        let instructionAccounts = accountIndexes.map { accounts[Int($0)] }
        
        return Instruction(
            program: program,
            accounts: instructionAccounts,
            data: data
        )
    }
}

extension Instruction: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "\(program.base58.prefix(8)) (\(accounts.count)) { \(data.hexEncodedString()) }"
    }
    
    public var debugDescription: String {
        description
    }
}

// MARK: - SolanaCodable -

extension CompiledInstruction {
    
    public init?(data: Data) {
        guard data.count > 1 else {
            return nil
        }
        
        var buffer = data
        
        // Program Index
        guard buffer.count >= 1 else {
            return nil
        }
        let index = buffer.consume(1)[0]
        
        // Account Indexes
        let (accountLen, remainingAfterAccountLen) = ShortVec.decodeLength(buffer)
        buffer = remainingAfterAccountLen
        
        guard buffer.count >= accountLen else {
            return nil
        }
        let accountIndexes = buffer.consume(accountLen).map { $0 }
        
        // Data
        let (dataLen, remainingAfterDataLen) = ShortVec.decodeLength(buffer)
        buffer = remainingAfterDataLen
        
        guard buffer.count >= dataLen else {
            return nil
        }
        let instructionData = buffer.consume(dataLen)
        
        self.programIndex = index
        self.accountIndexes = accountIndexes
        self.data = instructionData
    }
    
    public func encode() -> Data {
        var container = Data()
        
        container.append(programIndex)
        container.append(
            ShortVec.encode(Data(accountIndexes))
        )
        container.append(
            ShortVec.encode(data)
        )
        
        return container
    }
}

extension CompiledInstruction: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        return "\(programIndex) (\(accountIndexes.count)) { \(data.hexEncodedString()) }"
    }
    
    public var debugDescription: String {
        description
    }
}
