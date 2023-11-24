//
//  TimelockProgram.TransferWithAuthority.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct TransferWithAuthority: Equatable, Hashable, Codable {
        
        public var timelock: PublicKey
        public var vault: PublicKey
        public var vaultOwner: PublicKey
        public var timeAuthority: PublicKey
        public var destination: PublicKey
        public var payer: PublicKey
        public var bump: Byte
        public var kin: Kin

        public init(timelock: PublicKey, vault: PublicKey, vaultOwner: PublicKey, timeAuthority: PublicKey, destination: PublicKey, payer: PublicKey, bump: Byte, kin: Kin) {
            self.timelock = timelock
            self.vault = vault
            self.vaultOwner = vaultOwner
            self.timeAuthority = timeAuthority
            self.destination = destination
            self.payer = payer
            self.bump = bump
            self.kin = kin
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/master/pkg/solana/timelock/instruction_transferwithauthority.go
extension TimelockProgram.TransferWithAuthority: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.transferWithAuthority, instruction: instruction, expectingAccounts: 8)
        
        guard data.canConsume(1) else {
            throw ErrorGeneric.unknown
        }
        
        let bump   = data.consume(1).bytes[0]
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let quarks = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            timelock: instruction.accounts[0].publicKey,
            vault: instruction.accounts[1].publicKey,
            vaultOwner: instruction.accounts[2].publicKey,
            timeAuthority: instruction.accounts[3].publicKey,
            destination: instruction.accounts[4].publicKey,
            payer: instruction.accounts[5].publicKey,
            bump: bump,
            kin: Kin(quarks: quarks)
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: TimelockProgram.address,
            accounts: [
                .readonly(publicKey: timelock),
                .writable(publicKey: vault),
                .readonly(publicKey: vaultOwner, signer: true),
                .readonly(publicKey: timeAuthority, signer: true),
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
        
        data.append(contentsOf: TimelockProgram.Command.transferWithAuthority.rawValue.bytes)
        data.append(bump)
        data.append(contentsOf: kin.quarks.bytes)
        
        return data
    }
}
