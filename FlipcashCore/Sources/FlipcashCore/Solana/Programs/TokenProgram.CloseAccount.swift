//
//  TokenProgram.CloseAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TokenProgram {
    
    ///   Close an account by transferring all its SOL to the destination account.
    ///   Non-native accounts may only be closed if its token amount is zero.
    ///
    ///   0. [WRITE] The account to close.
    ///   1. [WRITE] The destination account.
    ///   2. [SIGNER] The account's owner.
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/master/token/program/src/instruction.rs
    ///
    public struct CloseAccount: Equatable, Hashable, Codable {
        
        public let account: PublicKey
        public let destination: PublicKey
        public let owner: PublicKey
        
        public init(account: PublicKey, destination: PublicKey, owner: PublicKey) {
            self.account = account
            self.destination = destination
            self.owner = owner
        }
    }
}

// MARK: - InstructionType -

extension TokenProgram.CloseAccount: InstructionType {
    
    public init(instruction: Instruction) throws {
        try TokenProgram.parse(.closeAccount, instruction: instruction, expectingAccounts: 3)
        
        self.init(
            account: instruction.accounts[0].publicKey,
            destination: instruction.accounts[1].publicKey,
            owner: instruction.accounts[2].publicKey
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TokenProgram.address,
            accounts: [
                .writable(publicKey: account),
                .writable(publicKey: destination),
                .readonly(publicKey: owner, signer: true)
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TokenProgram.Command.closeAccount.rawValue.bytes)
        
        return data
    }
}
