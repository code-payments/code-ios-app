//
//  TokenProgram.Transfer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TokenProgram {
    
    ///   Send tokens from one accounts to another. Accounts expected by this instruction:
    ///
    ///   ## Single owner/delegate
    ///
    ///   0. `[writable]` The source account.
    ///   1. `[writable]` The destination account.
    ///   2. `[signer]` The source account's owner/delegate.
    ///
    ///   ## Multisignature owner/delegate
    ///
    ///   0. `[writable]` The source account.
    ///   1. `[writable]` The destination account.
    ///   2. `[]` The source account's multisignature owner/delegate.
    ///   3. ..3+M `[signer]` M signer accounts.
    ///
    ///   Reference:
    ///   https://github.com/solana-labs/solana-program-library/blob/b011698251981b5a12088acba18fad1d41c3719a/token/program/src/instruction.rs#L76-L91
    ///
    public struct Transfer: Equatable, Hashable, Codable {
        
        public var owner: PublicKey
        public var source: PublicKey
        public var destination: PublicKey
        public var kin: Kin
        
        public init(owner: PublicKey, source: PublicKey, destination: PublicKey, kin: Kin) {
            self.owner = owner
            self.source = source
            self.destination = destination
            self.kin = kin
        }
    }
}

extension TokenProgram.Transfer: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TokenProgram.parse(.transfer, instruction: instruction, expectingAccounts: 3)
        
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let quarks = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            owner: instruction.accounts[2].publicKey,
            source: instruction.accounts[0].publicKey,
            destination: instruction.accounts[1].publicKey,
            kin: Kin(quarks: quarks)
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TokenProgram.address,
            accounts: [
                .writable(publicKey: source),
                .writable(publicKey: destination),
                .writable(publicKey: owner, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(TokenProgram.Command.transfer.rawValue)
        data.append(contentsOf: kin.quarks.bytes)
        
        return data
    }
}
