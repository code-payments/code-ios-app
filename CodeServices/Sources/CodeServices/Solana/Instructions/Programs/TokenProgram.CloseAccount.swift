//
//  TokenProgram.CloseAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TokenProgram {
    
    ///   Close an account by transferring all its SOL to the destination account.
    ///   Non-native accounts may only be closed if its token amount is zero.
    ///
    ///   Accounts expected by this instruction:
    ///
    ///   * Single owner
    ///   0. `[writable]` The account to close.
    ///   1. `[writable]` The destination account.
    ///   2. `[signer]` The account's owner.
    ///
    ///   * Multisignature owner
    ///   0. `[writable]` The account to close.
    ///   1. `[writable]` The destination account.
    ///   2. `[]` The account's multisignature owner.
    ///   3. ..3+M `[signer]` M signer accounts.
    ///
    public struct CloseAccount: Equatable, Hashable, Codable {
        
        public var account: PublicKey
        public var destination: PublicKey
        public var owner: PublicKey
        
        public init(account: PublicKey, destination: PublicKey, owner: PublicKey) {
            self.account = account
            self.destination = destination
            self.owner = owner
        }
    }
}

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
                .readonly(publicKey: owner),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(TokenProgram.Command.closeAccount.rawValue)
        
        return data
    }
}
