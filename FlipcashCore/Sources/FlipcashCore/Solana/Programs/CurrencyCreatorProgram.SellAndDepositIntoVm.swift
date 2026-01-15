//
//  CurrencyCreatorProgram.SellAndDepositIntoVm.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension CurrencyCreatorProgram {

    /// Sell tokens from a launchpad currency and deposit the proceeds into a VM account.
    /// This performs a bounded sell operation where the minimum output is controlled.
    ///
    /// Account structure (matching Android/server implementation):
    /// 0. `[writable, signer]` Seller/authority (payer and signer)
    /// 1. `[writable]` Pool account
    /// 2. `[]` Target token mint
    /// 3. `[]` Base mint (USDF/payment token)
    /// 4. `[writable]` Vault target (destination for target tokens)
    /// 5. `[writable]` Vault base (source of base tokens)
    /// 6. `[writable]` Seller target (seller's target token account)
    /// 7. `[writable, signer]` VM authority
    /// 8. `[writable]` VM account
    /// 9. `[writable]` VM memory account
    /// 10. `[writable]` VM omnibus account
    /// 11. `[]` VTA owner
    /// 12. `[]` Token program
    /// 13. `[]` VM program
    ///
    public struct SellAndDepositIntoVm: Equatable, Hashable, Codable {

        public let amount: UInt64
        public let minOutAmount: UInt64
        public let vmMemoryIndex: UInt16

        public let seller: PublicKey
        public let pool: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let vaultTarget: PublicKey
        public let vaultBase: PublicKey
        public let sellerTarget: PublicKey

        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let vmMemory: PublicKey
        public let vmOmnibus: PublicKey
        public let vtaOwner: PublicKey

        public init(
            amount: UInt64,
            minOutAmount: UInt64,
            vmMemoryIndex: UInt16,
            seller: PublicKey,
            pool: PublicKey,
            targetMint: PublicKey,
            baseMint: PublicKey,
            vaultTarget: PublicKey,
            vaultBase: PublicKey,
            sellerTarget: PublicKey,
            vmAuthority: PublicKey,
            vm: PublicKey,
            vmMemory: PublicKey,
            vmOmnibus: PublicKey,
            vtaOwner: PublicKey
        ) {
            self.seller = seller
            self.pool = pool
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.vaultTarget = vaultTarget
            self.vaultBase = vaultBase
            self.sellerTarget = sellerTarget
            self.vmAuthority = vmAuthority
            self.vm = vm
            self.vmMemory = vmMemory
            self.vmOmnibus = vmOmnibus
            self.vtaOwner = vtaOwner

            self.amount = amount
            self.minOutAmount = minOutAmount
            self.vmMemoryIndex = vmMemoryIndex
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.SellAndDepositIntoVm: InstructionType {

    public init(instruction: Instruction) throws {
        let data = try CurrencyCreatorProgram.parse(.sellAndDepositIntoVm, instruction: instruction, expectingAccounts: 14)

        guard data.count >= 18 else {
            throw CommandParseError.payloadNotFound
        }

        var offset = 0
        let amount = UInt64(bytes: Array(data[offset..<offset+8]))!
        offset += 8
        let minOutAmount = UInt64(bytes: Array(data[offset..<offset+8]))!
        offset += 8
        let vmMemoryIndex = UInt16(bytes: Array(data[offset..<offset+2]))!

        self.init(
            amount: amount,
            minOutAmount: minOutAmount,
            vmMemoryIndex: vmMemoryIndex,
            seller: instruction.accounts[0].publicKey,
            pool: instruction.accounts[1].publicKey,
            targetMint: instruction.accounts[2].publicKey,
            baseMint: instruction.accounts[3].publicKey,
            vaultTarget: instruction.accounts[4].publicKey,
            vaultBase: instruction.accounts[5].publicKey,
            sellerTarget: instruction.accounts[6].publicKey,
            vmAuthority: instruction.accounts[7].publicKey,
            vm: instruction.accounts[8].publicKey,
            vmMemory: instruction.accounts[9].publicKey,
            vmOmnibus: instruction.accounts[10].publicKey,
            vtaOwner: instruction.accounts[11].publicKey
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
            .writable(publicKey: vmAuthority, signer: true),
            .writable(publicKey: vm),
            .writable(publicKey: vmMemory),
            .writable(publicKey: vmOmnibus),
            .readonly(publicKey: vtaOwner),
            .readonly(publicKey: TokenProgram.address),
            .readonly(publicKey: VMProgram.address),
        ]

        return Instruction(
            program: CurrencyCreatorProgram.address,
            accounts: accounts,
            data: encode()
        )
    }

    public func encode() -> Data {
        var data = Data()

        data.append(contentsOf: CurrencyCreatorProgram.Command.sellAndDepositIntoVm.rawValue.bytes)
        data.append(contentsOf: amount.bytes)
        data.append(contentsOf: minOutAmount.bytes)
        data.append(contentsOf: vmMemoryIndex.bytes)

        return data
    }
}
