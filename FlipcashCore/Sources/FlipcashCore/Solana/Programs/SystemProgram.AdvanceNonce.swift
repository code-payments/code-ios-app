//
//  SystemProgram.AdvanceNonce.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//
import Foundation

extension SystemProgram {
    
    
    public struct AdvanceNonce: Codable, Equatable {
        let nonce: PublicKey
        let authority: PublicKey
        
        init(nonce: PublicKey, authority: PublicKey) {
            self.nonce = nonce
            self.authority = authority
        }
    }
}

extension SystemProgram.AdvanceNonce: InstructionType {
    public func instruction() -> Instruction {
        
        Instruction(
            program: SystemProgram.address,
            accounts: [
                .writable(publicKey: nonce),
                .readonly(publicKey: SysVar.recentBlockhashes.address),
                .writable(publicKey: authority, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: SystemProgram.Command.advanceNonceAccount.rawValue.bytes)
        return data
    }
    
    public init(instruction: Instruction) throws {
        try SystemProgram.parse(.advanceNonceAccount, instruction: instruction, expectingAccounts: 3)
        
        guard instruction.accounts.count == 3 else {
            throw NSError(domain: "Invalid accounts", code: 0)
        }
        
        self.init(
            nonce: instruction.accounts[0].publicKey,
            authority: instruction.accounts[2].publicKey  // Skip index 1 (sysvar)
        )
    }
}
