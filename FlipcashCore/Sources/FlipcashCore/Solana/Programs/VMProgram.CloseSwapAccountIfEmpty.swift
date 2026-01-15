//
//  VMProgram.CloseSwapAccountIfEmpty.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension VMProgram {
    
    ///   Close a VM swap account if it's empty, transferring any remaining SOL to the destination.
    ///
    ///   0. [WRITE, SIGNER] VM authority
    ///   1. [WRITE] VM account
    ///   2. [] Swapper
    ///   3. [] Swap PDA
    ///   4. [WRITE] Swap ATA
    ///   5. [WRITE] Destination account
    ///   6. [] Token program
    ///
    public struct CloseSwapAccountIfEmpty: Equatable, Hashable, Codable {
        
        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let swapper: PublicKey
        public let swapPda: PublicKey
        public let swapAta: PublicKey
        public let destination: PublicKey
        public let bump: Byte
        
        init(vmAuthority: PublicKey, vm: PublicKey, swapper: PublicKey, swapPda: PublicKey, swapAta: PublicKey, destination: PublicKey, bump: Byte) {
            self.vmAuthority = vmAuthority
            self.vm = vm
            self.swapper = swapper
            self.swapPda = swapPda
            self.swapAta = swapAta
            self.destination = destination
            self.bump = bump
        }
    }
}

// MARK: - InstructionType -

extension VMProgram.CloseSwapAccountIfEmpty: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try VMProgram.parse(.closeSwapAccountIfEmpty, instruction: instruction, expectingAccounts: 6)
        
        self.init(
            vmAuthority: instruction.accounts[0].publicKey,
            vm: instruction.accounts[1].publicKey,
            swapper: instruction.accounts[2].publicKey,
            swapPda: instruction.accounts[3].publicKey,
            swapAta: instruction.accounts[4].publicKey,
            destination: instruction.accounts[5].publicKey,
            bump: data[1]
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: VMProgram.address,
            accounts: [
                .writable(publicKey: vmAuthority, signer: true),
                .writable(publicKey: vm),
                .readonly(publicKey: swapper),
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
        
        data.append(contentsOf: VMProgram.Command.closeSwapAccountIfEmpty.rawValue.bytes)
        data.append(bump)
        
        return data
    }
}
