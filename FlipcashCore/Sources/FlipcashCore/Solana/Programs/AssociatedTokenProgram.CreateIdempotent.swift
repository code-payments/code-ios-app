//
//  AssociatedTokenProgram.CreateIdempotent.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension AssociatedTokenProgram {
    
    ///   Creates an associated token account for the given wallet address and token mint,
    ///   idempotently on the native chain, meaning if the account already exists, the instruction succeeds.
    ///
    ///   0. [WRITE, SIGNER] Funding account (must be a system account)
    ///   1. [WRITE] Associated token account address to be created or if it exists, the instruction succeeds
    ///   2. [] Wallet address for the new associated token account
    ///   3. [] The token mint for the new associated token account
    ///   4. [] System program
    ///   5. [] SPL Token program
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/master/associated-token-account/program/src/processor.rs
    ///
    public struct CreateIdempotent: Equatable, Hashable, Codable {
        
        public let subsidizer: PublicKey
        public let address: PublicKey  // The derived ATA address
        public let owner: PublicKey
        public let mint: PublicKey

        /// Creates a new CreateIdempotent instruction, deriving the ATA address from owner and mint
        public init(subsidizer: PublicKey, owner: PublicKey, mint: PublicKey) {
            self.subsidizer = subsidizer
            self.owner = owner
            self.mint = mint
            
            // Derive the associated token address from owner and mint
            self.address = PublicKey.deriveAssociatedAccount(from: owner, mint: mint)!.publicKey
        }
        
        /// Creates a CreateIdempotent instruction with an explicitly provided address (for deserialization)
        public init(subsidizer: PublicKey, address: PublicKey, owner: PublicKey, mint: PublicKey) {
            self.subsidizer = subsidizer
            self.address = address
            self.owner = owner
            self.mint = mint
        }
    }
}

// MARK: - InstructionType -

extension AssociatedTokenProgram.CreateIdempotent: InstructionType {
    
    public init(instruction: Instruction) throws {
        try AssociatedTokenProgram.parse(.createIdempotent, instruction: instruction, expectingAccounts: 7)
        
        self.init(
            subsidizer: instruction.accounts[0].publicKey,
            address: instruction.accounts[1].publicKey,
            owner: instruction.accounts[2].publicKey,
            mint: instruction.accounts[3].publicKey
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: AssociatedTokenProgram.address,
            accounts: [
                .writable(publicKey: subsidizer, signer: true),
                .writable(publicKey: address),
                .readonly(publicKey: owner),
                .readonly(publicKey: mint),
                .readonly(publicKey: SystemProgram.address),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SysVar.rent.address)
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: AssociatedTokenProgram.Command.createIdempotent.rawValue.bytes)
        
        return data
    }
}
