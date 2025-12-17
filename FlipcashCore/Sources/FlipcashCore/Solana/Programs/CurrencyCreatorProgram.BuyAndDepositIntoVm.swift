//
//  CurrencyCreatorProgram.BuyAndDepositIntoVm.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation

extension CurrencyCreatorProgram {
    
    /// Buy tokens from a launchpad currency and deposit them into a VM account.
    /// This performs a bounded buy operation where the maximum slippage is controlled.
    ///
    /// Account structure (matching server implementation):
    /// 0. `[writable, signer]` Buyer/authority (payer and signer)
    /// 1. `[writable]` Pool account
    /// 2. `[writable]` Currency state account
    /// 3. `[writable]` Target token mint
    /// 4. `[]` Base mint (USDC/payment token)
    /// 5. `[writable]` Vault target (destination for target tokens)
    /// 6. `[writable]` Vault base (source of base tokens)
    /// 7. `[writable]` Buyer base (buyer's base token account)
    /// 8. `[writable]` Fee target account
    /// 9. `[]` Fee base account
    /// 10. `[writable, signer]` VM authority
    /// 11. `[writable]` VM account
    /// 12. `[writable]` VM memory account
    /// 13. `[writable]` VM omnibus account
    /// 14. `[]` VTA owner
    /// 15. `[]` Token program
    /// 16. `[]` VM program
    /// 17. `[]` VM omnibus token account (ATA)
    ///
    public struct BuyAndDepositIntoVm: Equatable, Hashable, Codable {
        
        public let amount: UInt64
        public let minOutAmount: UInt64
        public let vmMemoryIndex: UInt16 
        
        public let buyer: PublicKey
        public let pool: PublicKey
        public let currency: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let vaultTarget: PublicKey
        public let vaultBase: PublicKey
        public let buyerBase: PublicKey
        public let feeTarget: PublicKey
        public let feeBase: PublicKey
        
        public let vmAuthority: PublicKey
        public let vm: PublicKey
        public let vmMemory: PublicKey
        public let vmOmnibus: PublicKey
        public let vtaOwner: PublicKey
        
        init(amount: UInt64, minOutAmount: UInt64, vmMemoryIndex: UInt16, buyer: PublicKey, pool: PublicKey, currency: PublicKey, targetMint: PublicKey, baseMint: PublicKey, vaultTarget: PublicKey, vaultBase: PublicKey, buyerBase: PublicKey, feeTarget: PublicKey, feeBase: PublicKey, vmAuthority: PublicKey, vm: PublicKey, vmMemory: PublicKey, vmOmnibus: PublicKey, vtaOwner: PublicKey) {
            self.buyer = buyer
            self.pool = pool
            self.currency = currency
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.vaultTarget = vaultTarget
            self.vaultBase = vaultBase
            self.buyerBase = buyerBase
            self.feeTarget = feeTarget
            self.feeBase = feeBase
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

extension CurrencyCreatorProgram.BuyAndDepositIntoVm: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try CurrencyCreatorProgram.parse(.buyAndDepositIntoVm, instruction: instruction, expectingAccounts: 17)
        
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
            buyer: instruction.accounts[0].publicKey,
            pool: instruction.accounts[1].publicKey,
            currency: instruction.accounts[2].publicKey,
            targetMint: instruction.accounts[3].publicKey,
            baseMint: instruction.accounts[4].publicKey,
            vaultTarget: instruction.accounts[5].publicKey,
            vaultBase: instruction.accounts[6].publicKey,
            buyerBase: instruction.accounts[7].publicKey,
            feeTarget: instruction.accounts[8].publicKey,
            feeBase: instruction.accounts[9].publicKey,
            vmAuthority: instruction.accounts[10].publicKey,
            vm: instruction.accounts[11].publicKey,
            vmMemory: instruction.accounts[12].publicKey,
            vmOmnibus: instruction.accounts[13].publicKey,
            vtaOwner: instruction.accounts[14].publicKey,
        )
    }
    
    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: buyer, signer: true),
            .writable(publicKey: pool),
            .writable(publicKey: currency,),
            .writable(publicKey: targetMint),
            .readonly(publicKey: baseMint),
            .writable(publicKey: vaultTarget),
            .writable(publicKey: vaultBase),
            .writable(publicKey: buyerBase),
            .writable(publicKey: feeTarget),
            .readonly(publicKey: feeBase),
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
        
        data.append(contentsOf: CurrencyCreatorProgram.Command.buyAndDepositIntoVm.rawValue.bytes)
        data.append(contentsOf: amount.bytes)
        data.append(contentsOf: minOutAmount.bytes)
        data.append(contentsOf: vmMemoryIndex.bytes)
        
        return data
    }
}
