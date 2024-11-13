//
//  SystemProgram.AdvanceNonce.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension SystemProgram {
    
    ///   Consumes a stored nonce, replacing it with a successor
    ///
    ///   0. [WRITE, SIGNER] Nonce account
    ///   1. [] RecentBlockhashes sysvar
    ///   2. [SIGNER] Nonce authority
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana/blob/f02a78d8fff2dd7297dc6ce6eb5a68a3002f5359/sdk/src/system_instruction.rs#L113-L119
    ///
    public struct AdvanceNonce: Equatable, Hashable, Codable {
        
        public let nonce: PublicKey
        public let authority: PublicKey
        
        public init(nonce: PublicKey, authority: PublicKey) {
            self.nonce = nonce
            self.authority = authority
        }
    }
}

// MARK: - InstructionType -

extension SystemProgram.AdvanceNonce: InstructionType {
    
    public init(instruction: Instruction) throws {
        try SystemProgram.parse(.advanceNonceAccount, instruction: instruction, expectingAccounts: 3)
        
        self.init(
            nonce: instruction.accounts[0].publicKey,
            authority: instruction.accounts[2].publicKey
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: SystemProgram.address,
            accounts: [
                .writable(publicKey: nonce),
                .readonly(publicKey: SysVar.recentBlockhashes.address),
                .readonly(publicKey: authority, signer: true)
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: SystemProgram.Command.advanceNonceAccount.rawValue.bytes)
        
        return data
    }
}
