//
//  VMProgram.TransferForSwapWithFee.swift
//  FlipcashCore
//

import Foundation

extension VMProgram {

    ///   Transfer tokens from a VM swap account to a swap destination and a
    ///   fee destination for swap operations with an associated fee.
    ///
    ///   0. [WRITE, SIGNER] VM authority
    ///   1. [] VM account
    ///   2. [WRITE, SIGNER] Swapper
    ///   3. [] Swap PDA
    ///   4. [WRITE] Swap ATA
    ///   5. [WRITE] Swap destination
    ///   6. [WRITE] Fee destination
    ///   7. [] Token program
    ///
    public struct TransferForSwapWithFee: Equatable, Hashable, Codable {

        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let swapper: PublicKey
        public let swapPda: PublicKey
        public let swapAta: PublicKey
        public let swapDestination: PublicKey
        public let feeDestination: PublicKey
        public let swapAmount: UInt64
        public let feeAmount: UInt64
        public let bump: Byte

        public init(
            vmAuthority: PublicKey,
            vm: PublicKey,
            swapper: PublicKey,
            swapPda: PublicKey,
            swapAta: PublicKey,
            swapDestination: PublicKey,
            feeDestination: PublicKey,
            swapAmount: UInt64,
            feeAmount: UInt64,
            bump: Byte
        ) {
            self.vmAuthority = vmAuthority
            self.vm = vm
            self.swapper = swapper
            self.swapPda = swapPda
            self.swapAta = swapAta
            self.swapDestination = swapDestination
            self.feeDestination = feeDestination
            self.swapAmount = swapAmount
            self.feeAmount = feeAmount
            self.bump = bump
        }
    }
}

// MARK: - InstructionType -

extension VMProgram.TransferForSwapWithFee: InstructionType {

    public init(instruction: Instruction) throws {
        let data = try VMProgram.parse(.transferForSwapWithFee, instruction: instruction, expectingAccounts: 8)

        // 1 (opcode already consumed) + 8 (swap_amount) + 8 (fee_amount) + 1 (bump)
        guard data.count >= 17 else {
            throw CommandParseError.payloadNotFound
        }

        self.init(
            vmAuthority: instruction.accounts[0].publicKey,
            vm: instruction.accounts[1].publicKey,
            swapper: instruction.accounts[2].publicKey,
            swapPda: instruction.accounts[3].publicKey,
            swapAta: instruction.accounts[4].publicKey,
            swapDestination: instruction.accounts[5].publicKey,
            feeDestination: instruction.accounts[6].publicKey,
            swapAmount: UInt64(bytes: Array(data.prefix(8)))!,
            feeAmount: UInt64(bytes: Array(data.dropFirst(8).prefix(8)))!,
            bump: data[16]
        )
    }

    public func instruction() -> Instruction {
        Instruction(
            program: VMProgram.address,
            accounts: [
                .writable(publicKey: vmAuthority, signer: true),
                .writable(publicKey: vm),
                .writable(publicKey: swapper, signer: true),
                .readonly(publicKey: swapPda),
                .writable(publicKey: swapAta),
                .writable(publicKey: swapDestination),
                .writable(publicKey: feeDestination),
                .readonly(publicKey: TokenProgram.address)
            ],
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()

        data.append(contentsOf: VMProgram.Command.transferForSwapWithFee.rawValue.bytes)
        data.append(contentsOf: swapAmount.bytes)
        data.append(contentsOf: feeAmount.bytes)
        data.append(bump)

        return data
    }
}
