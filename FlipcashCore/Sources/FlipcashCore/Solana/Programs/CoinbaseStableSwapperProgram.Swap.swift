//
//  CoinbaseStableSwapperProgram.Swap.swift
//  FlipcashCore
//

import Foundation

extension CoinbaseStableSwapperProgram {

    /// Anchor-format instruction for the Coinbase Stable Swapper's `swap` handler.
    ///
    ///   Account list (16, in this exact order):
    ///   0. [] pool
    ///   1. [] inVault
    ///   2. [] outVault
    ///   3. [WRITE] inVaultTokenAccount
    ///   4. [WRITE] outVaultTokenAccount
    ///   5. [WRITE] userFromTokenAccount
    ///   6. [WRITE] toTokenAccount
    ///   7. [WRITE] feeRecipientTokenAccount
    ///   8. [] feeRecipient
    ///   9. [] fromMint
    ///   10. [] toMint
    ///   11. [WRITE, SIGNER] user
    ///   12. [] whitelist
    ///   13. [] TokenProgram
    ///   14. [] AssociatedTokenProgram
    ///   15. [] SystemProgram
    ///
    public struct Swap {

        public let pool: PublicKey
        public let inVault: PublicKey
        public let outVault: PublicKey
        public let inVaultTokenAccount: PublicKey
        public let outVaultTokenAccount: PublicKey
        public let userFromTokenAccount: PublicKey
        public let toTokenAccount: PublicKey
        public let feeRecipientTokenAccount: PublicKey
        public let feeRecipient: PublicKey
        public let fromMint: PublicKey
        public let toMint: PublicKey
        public let user: PublicKey
        public let whitelist: PublicKey
        public let amountIn: UInt64
        public let minAmountOut: UInt64

        /// Anchor discriminator for `swap`: sha256("global:swap")[0..8]
        public static let discriminator: [UInt8] = [248, 198, 158, 145, 225, 117, 135, 200]

        public init(
            pool: PublicKey,
            inVault: PublicKey,
            outVault: PublicKey,
            inVaultTokenAccount: PublicKey,
            outVaultTokenAccount: PublicKey,
            userFromTokenAccount: PublicKey,
            toTokenAccount: PublicKey,
            feeRecipientTokenAccount: PublicKey,
            feeRecipient: PublicKey,
            fromMint: PublicKey,
            toMint: PublicKey,
            user: PublicKey,
            whitelist: PublicKey,
            amountIn: UInt64,
            minAmountOut: UInt64
        ) {
            self.pool = pool
            self.inVault = inVault
            self.outVault = outVault
            self.inVaultTokenAccount = inVaultTokenAccount
            self.outVaultTokenAccount = outVaultTokenAccount
            self.userFromTokenAccount = userFromTokenAccount
            self.toTokenAccount = toTokenAccount
            self.feeRecipientTokenAccount = feeRecipientTokenAccount
            self.feeRecipient = feeRecipient
            self.fromMint = fromMint
            self.toMint = toMint
            self.user = user
            self.whitelist = whitelist
            self.amountIn = amountIn
            self.minAmountOut = minAmountOut
        }
    }
}

// MARK: - InstructionType -

extension CoinbaseStableSwapperProgram.Swap: InstructionType {

    public init(instruction: Instruction) throws {
        throw CommandParseError.instructionMismatch
    }

    public func instruction() -> Instruction {
        Instruction(
            program: CoinbaseStableSwapperProgram.address,
            accounts: [
                .readonly(publicKey: pool),
                .readonly(publicKey: inVault),
                .readonly(publicKey: outVault),
                .writable(publicKey: inVaultTokenAccount),
                .writable(publicKey: outVaultTokenAccount),
                .writable(publicKey: userFromTokenAccount),
                .writable(publicKey: toTokenAccount),
                .writable(publicKey: feeRecipientTokenAccount),
                .readonly(publicKey: feeRecipient),
                .readonly(publicKey: fromMint),
                .readonly(publicKey: toMint),
                .writable(publicKey: user, signer: true),
                .readonly(publicKey: whitelist),
                .readonly(publicKey: TokenProgram.address),
                .readonly(publicKey: AssociatedTokenProgram.address),
                .readonly(publicKey: SystemProgram.address),
            ],
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: Self.discriminator)
        data.append(contentsOf: amountIn.bytes)
        data.append(contentsOf: minAmountOut.bytes)
        return data
    }
}
