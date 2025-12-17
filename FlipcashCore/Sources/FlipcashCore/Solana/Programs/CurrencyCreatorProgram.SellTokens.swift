//
//  CurrencyCreator.SellTokens.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/16/25.
//

import Foundation


extension CurrencyCreatorProgram {
    
    public struct SellTokens : Equatable, Codable {
        
        public let amount: UInt64
        public let minOutput: UInt64
        public let seller: PublicKey
        public let pool: PublicKey
        public let currency: PublicKey
        public let targetMint: PublicKey
        public let baseMint: PublicKey
        public let vaultTarget: PublicKey
        public let vaultBase: PublicKey
        public let sellerTarget: PublicKey
        public let sellerBase: PublicKey
        public let feeTarget: PublicKey
        public let feeBase: PublicKey
        
        init(amount: UInt64, minOutput: UInt64, seller: PublicKey, pool: PublicKey, currency: PublicKey, targetMint: PublicKey, baseMint: PublicKey, vaultTarget: PublicKey, vaultBase: PublicKey, sellerTarget: PublicKey, sellerBase: PublicKey, feeTarget: PublicKey, feeBase: PublicKey) {
            self.amount = amount
            self.minOutput = minOutput
            self.seller = seller
            self.pool = pool
            self.currency = currency
            self.targetMint = targetMint
            self.baseMint = baseMint
            self.vaultTarget = vaultTarget
            self.vaultBase = vaultBase
            self.sellerTarget = sellerTarget
            self.sellerBase = sellerBase
            self.feeTarget = feeTarget
            self.feeBase = feeBase
        }
    }
}

// MARK: - InstructionType -

extension CurrencyCreatorProgram.SellTokens: InstructionType {
    
    public init(instruction: Instruction) throws {
        let data = try CurrencyCreatorProgram.parse(.sellAndDepositIntoVm, instruction: instruction, expectingAccounts: 12)
        
        guard data.count >= 18 else {
            throw CommandParseError.payloadNotFound
        }
        
        var offset = 0
        let amount = UInt64(bytes: Array(data[offset..<offset+8]))!
        offset += 8
        let minOutAmount = UInt64(bytes: Array(data[offset..<offset+8]))!
        
       
        self.init(
            amount: amount,
            minOutput: minOutAmount,
            seller: instruction.accounts[0].publicKey,
            pool: instruction.accounts[1].publicKey,
            currency: instruction.accounts[2].publicKey,
            targetMint: instruction.accounts[3].publicKey,
            baseMint: instruction.accounts[4].publicKey,
            vaultTarget: instruction.accounts[5].publicKey,
            vaultBase: instruction.accounts[6].publicKey,
            sellerTarget: instruction.accounts[7].publicKey,
            sellerBase: instruction.accounts[8].publicKey,
            feeTarget: instruction.accounts[9].publicKey,
            feeBase: instruction.accounts[10].publicKey,
        )
    }
    
    public func instruction() -> Instruction {
        let accounts: [AccountMeta] = [
            .writable(publicKey: seller, signer: true),
            .writable(publicKey: pool),
            .writable(publicKey: currency),
            .writable(publicKey: targetMint),
            
            .readonly(publicKey: baseMint),
            
            .writable(publicKey: vaultTarget),
            .writable(publicKey: vaultBase),
            .writable(publicKey: sellerTarget),
            .writable(publicKey: sellerBase),
            
            .readonly(publicKey: feeTarget),
            
            .writable(publicKey: feeBase),
            
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
        data.append(contentsOf: amount.bytes) // 8
        data.append(contentsOf: minOutput.bytes) // 8
        
        return data
    }
}
