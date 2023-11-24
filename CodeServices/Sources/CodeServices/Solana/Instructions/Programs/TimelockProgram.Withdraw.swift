//
//  TimelockProgram.Withdraw.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct Withdraw: Equatable, Hashable, Codable {
        
        public var timelock: PublicKey
        public var vault: PublicKey
        public var vaultOwner: PublicKey
        public var destination: PublicKey
        public var payer: PublicKey
        public var bump: Byte
        public var legacy: Bool

        public init(timelock: PublicKey, vault: PublicKey, vaultOwner: PublicKey, destination: PublicKey, payer: PublicKey, bump: Byte, legacy: Bool = false) {
            self.timelock = timelock
            self.vault = vault
            self.vaultOwner = vaultOwner
            self.destination = destination
            self.payer = payer
            self.bump = bump
            self.legacy = legacy
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/privacy-v3/pkg/solana/timelock/instruction_withdraw.go
extension TimelockProgram.Withdraw: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.withdraw, instruction: instruction, expectingAccounts: 7)
        
        let stride = MemoryLayout<Byte>.stride
        
        guard data.canConsume(stride), let bump = Byte(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            timelock: instruction.accounts[0].publicKey,
            vault: instruction.accounts[1].publicKey,
            vaultOwner: instruction.accounts[2].publicKey,
            destination: instruction.accounts[3].publicKey,
            payer: instruction.accounts[4].publicKey,
            bump: bump
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: legacy ? TimelockProgram.legacyAddress : TimelockProgram.address,
            accounts: [
                .readonly(publicKey: timelock),
                .writable(publicKey: vault),
                .readonly(publicKey: vaultOwner, signer: true),
                .writable(publicKey: destination),
                .writable(publicKey: payer, signer: true),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TimelockProgram.Command.withdraw.rawValue.bytes)
        data.append(contentsOf: bump.bytes)
        
        return data
    }
}
