//
//  AssociatedTokenProgram.CreateAccount.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension AssociatedTokenProgram {
    
    ///   Create an associated token account for the given wallet address and token mint
    ///   Accounts expected by this instruction:
    ///
    ///   0. `[writeable,signer]` Funding account (must be a system account)
    ///   1. `[writeable]` Associated token account address to be created
    ///   2. `[]` Wallet address for the new associated token account
    ///   3. `[]` The token mint for the new associated token account
    ///   4. `[]` System program
    ///   5. `[]` SPL Token program
    ///   6. `[]` Rent sysvar
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/0639953c7dd0f5228c3ceda3ba68fece3b46ff1d/associated-token-account/program/src/lib.rs#L54
    ///
    public struct CreateAccount: Equatable, Hashable, Codable {
        
        public let subsidizer: PublicKey
        public let owner: PublicKey
        public let associatedTokenAccount: PublicKey
        public let mint: PublicKey
        
        public init(subsidizer: PublicKey, owner: PublicKey, associatedTokenAccount: PublicKey, mint: PublicKey) {
            self.subsidizer = subsidizer
            self.owner = owner
            self.associatedTokenAccount = associatedTokenAccount
            self.mint = mint
        }
    }
}

// MARK: - InstructionType -

extension AssociatedTokenProgram.CreateAccount: InstructionType {
    
    public init(instruction: Instruction) throws {
        try AssociatedTokenProgram.parse(instruction: instruction, expectingAccounts: 7)
        
        let accounts = instruction.accounts.map { $0.publicKey }
        self.init(
            subsidizer: accounts[0],
            owner: accounts[1],
            associatedTokenAccount: accounts[2],
            mint: accounts[3]
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: AssociatedTokenProgram.address,
            accounts: [
                .writable(publicKey: subsidizer, signer: true),
                .writable(publicKey: associatedTokenAccount),
                .readonly(publicKey: owner),
                .readonly(publicKey: mint),
                .readonly(publicKey: SystemProgram.address),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SysVar.rent.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        Data()
    }
}
