//
//  TimelockProgram.DeactivateLock.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct DeactivateLock: Equatable, Hashable, Codable {
        
        public var timelock: PublicKey
        public var vaultOwner: PublicKey
        public var payer: PublicKey
        public var bump: Byte
        public var legacy: Bool

        public init(timelock: PublicKey, vaultOwner: PublicKey, payer: PublicKey, bump: Byte, legacy: Bool = false) {
            self.timelock = timelock
            self.vaultOwner = vaultOwner
            self.payer = payer
            self.bump = bump
            self.legacy = legacy
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/privacy-v3/pkg/solana/timelock/instruction_deactivate.go
extension TimelockProgram.DeactivateLock: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.deactivateLock, instruction: instruction, expectingAccounts: 3)
        
        let stride = MemoryLayout<Byte>.stride
        
        guard data.canConsume(stride), let bump = Byte(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            timelock: instruction.accounts[0].publicKey,
            vaultOwner: instruction.accounts[1].publicKey,
            payer: instruction.accounts[2].publicKey,
            bump: bump
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: legacy ? TimelockProgram.legacyAddress : TimelockProgram.address,
            accounts: [
                .writable(publicKey: timelock),
                .readonly(publicKey: vaultOwner, signer: true),
                .writable(publicKey: payer, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TimelockProgram.Command.deactivateLock.rawValue.bytes)
        data.append(contentsOf: bump.bytes)
        
        return data
    }
}
