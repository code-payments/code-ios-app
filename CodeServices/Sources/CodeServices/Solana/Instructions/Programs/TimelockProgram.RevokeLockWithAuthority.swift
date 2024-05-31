//
//  TimelockProgram.RevokeLockWithAuthority.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct RevokeLockWithAuthority: Equatable, Hashable, Codable {
        
        public var timelock: PublicKey
        public var vault: PublicKey
        public var closeAuthority: PublicKey
        public var payer: PublicKey
        public var bump: Byte

        public init(timelock: PublicKey, vault: PublicKey, closeAuthority: PublicKey, payer: PublicKey, bump: Byte) {
            self.timelock = timelock
            self.vault = vault
            self.closeAuthority = closeAuthority
            self.payer = payer
            self.bump = bump
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/privacy-v3/pkg/solana/timelock/instruction_revokelockwithauthority.go
extension TimelockProgram.RevokeLockWithAuthority: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.revokeLockWithAuthority, instruction: instruction, expectingAccounts: 6)
        
        let stride = MemoryLayout<Byte>.stride
        
        guard data.canConsume(stride), let bump = Byte(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            timelock: instruction.accounts[0].publicKey,
            vault: instruction.accounts[1].publicKey,
            closeAuthority: instruction.accounts[2].publicKey,
            payer: instruction.accounts[3].publicKey,
            bump: bump
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TimelockProgram.address,
            accounts: [
                .writable(publicKey: timelock),
                .writable(publicKey: vault),
                .readonly(publicKey: closeAuthority, signer: true),
                .writable(publicKey: payer, signer: true),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TimelockProgram.Command.revokeLockWithAuthority.rawValue.bytes)
        data.append(contentsOf: bump.bytes)
        
        return data
    }
}
