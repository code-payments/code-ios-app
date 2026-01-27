//
//  TokenProgram.Transfer.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-26.
//

import Foundation

extension TokenProgram {
    /// Simple SPL Token transfer instruction
    public struct Transfer: Equatable, Hashable, Codable {
        public let amount: UInt64
        public let owner: PublicKey
        public let source: PublicKey
        public let destination: PublicKey

        public init(
            amount: UInt64,
            owner: PublicKey,
            source: PublicKey,
            destination: PublicKey
        ) {
            self.amount = amount
            self.owner = owner
            self.source = source
            self.destination = destination
        }
    }
}

// MARK: - InstructionType

extension TokenProgram.Transfer: InstructionType {
    public init(instruction: Instruction) throws {
        throw CommandParseError.instructionMismatch
    }

    public func instruction() -> Instruction {
        Instruction(
            program: TokenProgram.address,
            accounts: [
                .writable(publicKey: source, signer: false),
                .writable(publicKey: destination, signer: false),
                .readonly(publicKey: owner, signer: true),
            ],
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(TokenProgram.Command.transfer.rawValue)
        data.append(contentsOf: amount.bytes)
        return data
    }
}
