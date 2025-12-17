//
//  VMProgram.TransferForSwap.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension VMProgram {
    
    ///   Transfer tokens from a VM swap account to a destination account for swap operations.
    ///
    ///   0. [WRITE, SIGNER] VM authority
    ///   1. [] VM  account
    ///   2. [WRITE, SIGNER] Swapper
    ///   3. [] Swap PDA
    ///   4. [WRITE] Swap ATA
    ///   5. [WRITE] Destination
    ///   6. [] Token program
    ///
    public struct TransferForSwap: Equatable, Hashable, Codable {
        
        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let swapper: PublicKey
        public let swapPda: PublicKey
        public let swapAta: PublicKey
        public let destination: PublicKey
        public let amount: UInt64
        public let bump: Byte
        
        public init(vmAuthority: PublicKey, vm: PublicKey, swapper: PublicKey, swapPda: PublicKey, swapAta: PublicKey, destination: PublicKey, amount: UInt64, bump: Byte) {
            self.vmAuthority = vmAuthority
            self.vm = vm
            self.swapper = swapper
            self.swapPda = swapPda
            self.swapAta = swapAta
            self.destination = destination
            self.amount = amount
            self.bump = bump
        }
    }
}

// MARK: - InstructionType -

extension VMProgram.TransferForSwap: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try VMProgram.parse(.transferForSwap, instruction: instruction, expectingAccounts:7)
        
        guard data.count >= 9 else {
            throw CommandParseError.payloadNotFound
        }
        
        self.init(
            vmAuthority: instruction.accounts[0].publicKey,
            vm: instruction.accounts[1].publicKey,
            swapper: instruction.accounts[2].publicKey,
            swapPda: instruction.accounts[3].publicKey,
            swapAta: instruction.accounts[4].publicKey,
            destination: instruction.accounts[5].publicKey,
            amount: UInt64(bytes: Array(data.prefix(8)))!,
            bump: data[1]
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: VMProgram.address,
            accounts: [
                .writable(publicKey: vmAuthority, signer: true),
                .readonly(publicKey: vm),
                .writable(publicKey: swapper, signer: true),
                .readonly(publicKey: swapPda),
                .writable(publicKey: swapAta),
                .writable(publicKey: destination),
                .readonly(publicKey: TokenProgram.address)
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: VMProgram.Command.transferForSwap.rawValue.bytes)
        data.append(contentsOf: amount.bytes)
        data.append(bump)
        
        return data
    }
}
