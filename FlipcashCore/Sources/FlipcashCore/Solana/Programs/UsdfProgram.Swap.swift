//
//  UsdfProgram.Swap.swift
//  FlipcashCore
//
//  Created by Claude on 2025-01-26.
//

import Foundation

extension UsdfProgram {
    /// Instruction to swap between USDF and another token (e.g., USDC)
    public struct Swap: Equatable, Hashable, Codable {
        public let amount: UInt64
        public let usdfToOther: Bool
        public let user: PublicKey
        public let pool: PublicKey
        public let usdfVault: PublicKey
        public let otherVault: PublicKey
        public let userUsdfToken: PublicKey
        public let userOtherToken: PublicKey

        public init(
            amount: UInt64,
            usdfToOther: Bool,
            user: PublicKey,
            pool: PublicKey,
            usdfVault: PublicKey,
            otherVault: PublicKey,
            userUsdfToken: PublicKey,
            userOtherToken: PublicKey
        ) {
            self.amount = amount
            self.usdfToOther = usdfToOther
            self.user = user
            self.pool = pool
            self.usdfVault = usdfVault
            self.otherVault = otherVault
            self.userUsdfToken = userUsdfToken
            self.userOtherToken = userOtherToken
        }
    }
}

// MARK: - InstructionType

extension UsdfProgram.Swap: InstructionType {
    public init(instruction: Instruction) throws {
        throw CommandParseError.instructionMismatch
    }

    public func instruction() -> Instruction {
        Instruction(
            program: UsdfProgram.address,
            accounts: [
                .writable(publicKey: user, signer: true),
                .readonly(publicKey: pool, signer: false),
                .writable(publicKey: usdfVault, signer: false),
                .writable(publicKey: otherVault, signer: false),
                .writable(publicKey: userUsdfToken, signer: false),
                .writable(publicKey: userOtherToken, signer: false),
                .readonly(publicKey: TokenProgram.address, signer: false),
            ],
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(UsdfProgram.Command.swap.rawValue)
        data.append(contentsOf: amount.bytes)
        data.append(usdfToOther ? 1 : 0)
        return data
    }
}
