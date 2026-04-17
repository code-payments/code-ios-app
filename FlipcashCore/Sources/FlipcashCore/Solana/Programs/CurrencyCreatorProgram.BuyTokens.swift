//
//  CurrencyCreatorProgram.BuyTokens.swift
//  FlipcashCore
//

import Foundation

extension CurrencyCreatorProgram {

    /// Swap base-mint tokens (USDF) for target-mint (launchpad currency) tokens,
    /// depositing the output directly into `buyerTarget`. This is a distinct
    /// instruction from `BuyAndDepositIntoVm` — the latter wraps an additional
    /// VM deposit step, whereas `BuyTokens` just transfers to a pre-existing ATA.
    ///
    /// Used by the new-currency launch transaction where `buyerTarget` is the
    /// owner's VM Deposit ATA for the new mint (already created in the same
    /// transaction) and `buyerBase` is the owner's USDF ATA.
    ///
    /// Account structure (mirrors api/src/sdk.rs build_buy_tokens_ix):
    /// 0. [WRITE, SIGNER] Buyer
    /// 1. []              Pool PDA
    /// 2. []              Target mint
    /// 3. []              Base mint
    /// 4. [WRITE]         Vault A PDA (target vault)
    /// 5. [WRITE]         Vault B PDA (base vault)
    /// 6. [WRITE]         Buyer target token account
    /// 7. [WRITE]         Buyer base token account
    /// 8. []              SPL Token program
    public struct BuyTokens: Equatable, Hashable, Codable {

        public let buyer: PublicKey
        public let pool: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let vaultA: PublicKey
        public let vaultB: PublicKey
        public let buyerTarget: PublicKey
        public let buyerBase: PublicKey
        public let amount: UInt64
        public let minOutAmount: UInt64

        public init(
            buyer: PublicKey,
            pool: PublicKey,
            targetMint: PublicKey,
            baseMint: PublicKey,
            vaultA: PublicKey,
            vaultB: PublicKey,
            buyerTarget: PublicKey,
            buyerBase: PublicKey,
            amount: UInt64,
            minOutAmount: UInt64
        ) {
            self.buyer = buyer
            self.pool = pool
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.vaultA = vaultA
            self.vaultB = vaultB
            self.buyerTarget = buyerTarget
            self.buyerBase = buyerBase
            self.amount = amount
            self.minOutAmount = minOutAmount
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.BuyTokens: InstructionType {

    public init(instruction: Instruction) throws {
        let data = try CurrencyCreatorProgram.parse(.buyTokens, instruction: instruction, expectingAccounts: 9)

        guard data.count >= 16 else {
            throw CommandParseError.payloadNotFound
        }

        let bytes = Array(data)
        let amount = UInt64(bytes: Array(bytes[0..<8]))!
        let minOut = UInt64(bytes: Array(bytes[8..<16]))!

        self.init(
            buyer: instruction.accounts[0].publicKey,
            pool: instruction.accounts[1].publicKey,
            targetMint: instruction.accounts[2].publicKey,
            baseMint: instruction.accounts[3].publicKey,
            vaultA: instruction.accounts[4].publicKey,
            vaultB: instruction.accounts[5].publicKey,
            buyerTarget: instruction.accounts[6].publicKey,
            buyerBase: instruction.accounts[7].publicKey,
            amount: amount,
            minOutAmount: minOut
        )
    }

    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: buyer, signer: true),
            .readonly(publicKey: pool),
            .readonly(publicKey: targetMint),
            .readonly(publicKey: baseMint),
            .writable(publicKey: vaultA),
            .writable(publicKey: vaultB),
            .writable(publicKey: buyerTarget),
            .writable(publicKey: buyerBase),
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
        data.append(contentsOf: CurrencyCreatorProgram.Command.buyTokens.rawValue.bytes)
        data.append(contentsOf: amount.bytes)
        data.append(contentsOf: minOutAmount.bytes)
        return data
    }
}
