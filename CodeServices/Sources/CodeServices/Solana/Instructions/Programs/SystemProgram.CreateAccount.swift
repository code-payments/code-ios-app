//
//  SystemProgram.CreateAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension SystemProgram {
    
    ///   Account references
    ///
    ///   0. [WRITE, SIGNER] Funding account
    ///   1. [WRITE, SIGNER] New account
    ///
    ///   CreateAccount {
    ///     lamports: u64, // Number of lamports to transfer to the new account
    ///     space: u64,    // Number of bytes of memory to allocate
    ///     owner: Pubkey, // Address of program that will own the new account
    ///   }
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana/blob/f02a78d8fff2dd7297dc6ce6eb5a68a3002f5359/sdk/src/system_instruction.rs#L58-L72
    ///
    public struct CreateAccount: Equatable, Hashable, Codable {
        
        public let subsidizer: PublicKey
        public let address: PublicKey
        public let owner: PublicKey
        public let lamports: UInt64
        public let size: UInt64
        
        public init(subsidizer: PublicKey, address: PublicKey, owner: PublicKey, lamports: UInt64, size: UInt64) {
            self.subsidizer = subsidizer
            self.address = address
            self.owner = owner
            self.lamports = lamports
            self.size = size
        }
    }
}

// MARK: - InstructionType -

extension SystemProgram.CreateAccount: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data   = try SystemProgram.parse(.createAccount, instruction: instruction, expectingAccounts: 2)
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let lamports = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        guard data.canConsume(stride), let size = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        guard data.canConsume(stride), let owner = PublicKey(data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            subsidizer: instruction.accounts[0].publicKey,
            address: instruction.accounts[1].publicKey,
            owner: owner,
            lamports: lamports,
            size: size
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: SystemProgram.address,
            accounts: [
                .writable(publicKey: subsidizer, signer: true),
                .writable(publicKey: address, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: SystemProgram.Command.createAccount.rawValue.bytes)
        data.append(contentsOf: lamports.bytes)
        data.append(contentsOf: size.bytes)
        data.append(contentsOf: owner.bytes)
        
        return data
    }
}
