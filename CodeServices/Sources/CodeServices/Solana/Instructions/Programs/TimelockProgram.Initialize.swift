//
//  TimelockProgram.Initialize.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct Initialize: Equatable, Hashable, Codable {
        
        public var nonce: PublicKey
        public var timelock: PublicKey
        public var vault: PublicKey
        public var vaultOwner: PublicKey
        public var mint: PublicKey
        public var timeAuthority: PublicKey
        public var payer: PublicKey
        public var lockout: UInt64

        public init(nonce: PublicKey, timelock: PublicKey, vault: PublicKey, vaultOwner: PublicKey, mint: PublicKey, timeAuthority: PublicKey, payer: PublicKey, lockout: UInt64) {
            self.nonce = nonce
            self.timelock = timelock
            self.vault = vault
            self.vaultOwner = vaultOwner
            self.mint = mint
            self.timeAuthority = timeAuthority
            self.payer = payer
            self.lockout = lockout
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/master/pkg/solana/timelock/instruction_initialize.go
extension TimelockProgram.Initialize: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.initialize, instruction: instruction, expectingAccounts: 10)
        
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let lockout = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            nonce: instruction.accounts[0].publicKey,
            timelock: instruction.accounts[1].publicKey,
            vault: instruction.accounts[2].publicKey,
            vaultOwner: instruction.accounts[3].publicKey,
            mint: instruction.accounts[4].publicKey,
            timeAuthority: instruction.accounts[5].publicKey,
            payer: instruction.accounts[6].publicKey,
            lockout: lockout
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TimelockProgram.address,
            accounts: [
                .readonly(publicKey: nonce),
                .writable(publicKey: timelock),
                .writable(publicKey: vault),
                .readonly(publicKey: vaultOwner),
                .readonly(publicKey: mint),
                .readonly(publicKey: timeAuthority, signer: true),
                .writable(publicKey: payer, signer: true),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
                .readonly(publicKey: SysVar.rent.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TimelockProgram.Command.initialize.rawValue.bytes)
        data.append(contentsOf: lockout.bytes)
        
        return data
    }
}
