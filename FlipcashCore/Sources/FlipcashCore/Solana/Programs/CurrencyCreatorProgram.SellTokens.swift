//
//  CurrencyCreatorProgram.SellTokens.swift
//  FlipcashCore
//

import Foundation

extension CurrencyCreatorProgram {

    /// Sell target-mint (launchpad currency) tokens for base-mint (USDF) tokens,
    /// transferring the proceeds into a pre-existing `sellerBase` ATA. Distinct
    /// from `SellAndDepositIntoVm` — no VM deposit step; proceeds land in an ATA.
    ///
    /// Used by the launchpad→launchpad swap transaction where `sellerBase` is
    /// the temporary Core Mint ATA that funds the subsequent `BuyAndDepositIntoVm`.
    ///
    /// Account structure (mirrors OCP SellTokensInstructionAccounts):
    /// 0. [WRITE, SIGNER] Seller
    /// 1. [WRITE]         Pool PDA
    /// 2. []              Target mint
    /// 3. []              Base mint
    /// 4. [WRITE]         Vault target PDA
    /// 5. [WRITE]         Vault base PDA
    /// 6. [WRITE]         Seller target token account
    /// 7. [WRITE]         Seller base token account
    /// 8. []              SPL Token program
    public struct SellTokens: Equatable, Hashable, Codable {

        public let seller: PublicKey
        public let pool: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let vaultTarget: PublicKey
        public let vaultBase: PublicKey
        public let sellerTarget: PublicKey
        public let sellerBase: PublicKey
        public let inAmount: UInt64
        public let minAmountOut: UInt64

        public init(
            seller: PublicKey,
            pool: PublicKey,
            targetMint: PublicKey,
            baseMint: PublicKey,
            vaultTarget: PublicKey,
            vaultBase: PublicKey,
            sellerTarget: PublicKey,
            sellerBase: PublicKey,
            inAmount: UInt64,
            minAmountOut: UInt64
        ) {
            self.seller = seller
            self.pool = pool
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.vaultTarget = vaultTarget
            self.vaultBase = vaultBase
            self.sellerTarget = sellerTarget
            self.sellerBase = sellerBase
            self.inAmount = inAmount
            self.minAmountOut = minAmountOut
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.SellTokens: InstructionType {

    public init(instruction: Instruction) throws {
        let data = try CurrencyCreatorProgram.parse(.sellTokens, instruction: instruction, expectingAccounts: 9)

        guard data.count >= 16 else {
            throw CommandParseError.payloadNotFound
        }

        let bytes = Array(data)
        let inAmount = UInt64(bytes: Array(bytes[0..<8]))!
        let minAmountOut = UInt64(bytes: Array(bytes[8..<16]))!

        self.init(
            seller: instruction.accounts[0].publicKey,
            pool: instruction.accounts[1].publicKey,
            targetMint: instruction.accounts[2].publicKey,
            baseMint: instruction.accounts[3].publicKey,
            vaultTarget: instruction.accounts[4].publicKey,
            vaultBase: instruction.accounts[5].publicKey,
            sellerTarget: instruction.accounts[6].publicKey,
            sellerBase: instruction.accounts[7].publicKey,
            inAmount: inAmount,
            minAmountOut: minAmountOut
        )
    }

    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: seller, signer: true),
            .writable(publicKey: pool),
            .readonly(publicKey: targetMint),
            .readonly(publicKey: baseMint),
            .writable(publicKey: vaultTarget),
            .writable(publicKey: vaultBase),
            .writable(publicKey: sellerTarget),
            .writable(publicKey: sellerBase),
            .readonly(publicKey: TokenProgram.address),
        ]

        return Instruction(
            program: CurrencyCreatorProgram.address,
            accounts: accounts,
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: CurrencyCreatorProgram.Command.sellTokens.rawValue.bytes)
        data.append(contentsOf: inAmount.bytes)
        data.append(contentsOf: minAmountOut.bytes)
        return data
    }
}
