//
//  TimelockProgram.BurnDustWithAuthority.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension TimelockProgram {
    public struct BurnDustWithAuthority: Equatable, Hashable, Codable {
        
        public var timelock: PublicKey
        public var vault: PublicKey
        public var vaultOwner: PublicKey
        public var timeAuthority: PublicKey
        public var mint: PublicKey
        public var payer: PublicKey
        public var bump: Byte
        public var maxAmount: Kin
        public var legacy: Bool

        public init(timelock: PublicKey, vault: PublicKey, vaultOwner: PublicKey, timeAuthority: PublicKey, mint: PublicKey, payer: PublicKey, bump: Byte, maxAmount: Kin, legacy: Bool = false) {
            self.timelock = timelock
            self.vault = vault
            self.vaultOwner = vaultOwner
            self.timeAuthority = timeAuthority
            self.mint = mint
            self.payer = payer
            self.bump = bump
            self.maxAmount = maxAmount
            self.legacy = legacy
        }
    }
}

/// Reference: https://github.com/code-wallet/code-server/blob/privacy-v3/pkg/solana/timelock/instruction_burndustwithauthority.go
extension TimelockProgram.BurnDustWithAuthority: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try TimelockProgram.parse(.burnDustWithAuthority, instruction: instruction, expectingAccounts: 8)
        
        guard data.canConsume(1) else {
            throw ErrorGeneric.unknown
        }
        
        let bump   = data.consume(1).bytes[0]
        let stride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(stride), let maxAmount = UInt64(data: data.consume(stride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            timelock: instruction.accounts[0].publicKey,
            vault: instruction.accounts[1].publicKey,
            vaultOwner: instruction.accounts[2].publicKey,
            timeAuthority: instruction.accounts[3].publicKey,
            mint: instruction.accounts[4].publicKey,
            payer: instruction.accounts[5].publicKey,
            bump: bump,
            maxAmount: Kin(quarks: maxAmount)
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: legacy ? TimelockProgram.legacyAddress : TimelockProgram.address,
            accounts: [
                .writable(publicKey: timelock),
                .writable(publicKey: vault),
                .readonly(publicKey: vaultOwner, signer: true),
                .readonly(publicKey: timeAuthority, signer: true),
                .writable(publicKey: mint),
                .writable(publicKey: payer, signer: true),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: TimelockProgram.Command.burnDustWithAuthority.rawValue.bytes)
        data.append(bump)
        data.append(contentsOf: maxAmount.quarks.bytes)
        
        return data
    }
}
