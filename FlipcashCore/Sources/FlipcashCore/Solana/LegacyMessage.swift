//
//  LegacyMessage.swift
//  FlipcashCore
//
//  Created by Brandon McAnsh on 12/1/25.
//

import Foundation

public struct LegacyMessage: Equatable, Sendable {
    
    public var header: Message.Header
    public var accounts: [AccountMeta]
    public var recentBlockhash: Hash
    public var instructions: [Instruction]
    
    // MARK: - Init -
    
    public init(accounts: [AccountMeta], recentBlockhash: Hash, instructions: [Instruction]) {
        // Sort the account meta's based on:
        //   1. Payer is always the first account / signer.
        //   1. All signers are before non-signers.
        //   2. Writable accounts before read-only accounts.
        //   3. Programs last
        let uniqueAccounts = accounts.filterUniqueAccounts().sorted()
        
        let signers         = uniqueAccounts.filter { $0.isSigner }
        let readOnlySigners = uniqueAccounts.filter { !$0.isWritable && $0.isSigner }
        let readOnly        = uniqueAccounts.filter { !$0.isWritable && !$0.isSigner }
        
        self.header = Message.Header(
            requiredSignatures: signers.count,
            readOnlySigners: readOnlySigners.count,
            readOnly: readOnly.count
        )
        
        self.accounts = uniqueAccounts
        self.recentBlockhash = recentBlockhash
        self.instructions = instructions
    }
}

// MARK: - SolanaCodable -

extension LegacyMessage {
    
    public init?(data: Data) {
        print("unmarshalling legacy message")
        var payload = data
        
        // Decode `header`
        guard let header = Message.Header(data: payload.consume(Message.Header.length)) else {
            return nil
        }
        
        // Decode `accountKeys`
        let (accountCount, accountData) = ShortVec.decodeLength(payload)
        print("account count: \(accountCount), account data: \(accountData.debugDescription)")
        guard let messageAccounts = accountData.chunk(size: PublicKey.length, count: accountCount, block: { try! PublicKey($0) }) else {
            return nil
        }
        
        payload = accountData.tail(from: PublicKey.length * accountCount)
        
        // Decode `recentBlockHash`
        guard let hash = try? Hash(payload.consume(Hash.length)) else {
            return nil
        }
        
        // Decode `instructions`
        let (instructionCount, instructionsData) = ShortVec.decodeLength(payload)
        
        var remainingData = instructionsData
        var compiledInstructions: [CompiledInstruction] = []
        
        for _ in 0..<instructionCount {
            guard let instruction = CompiledInstruction(data: remainingData) else {
                return nil
            }
            
            guard instruction.programIndex < messageAccounts.count else {
                return nil
            }
            
            remainingData = remainingData.tail(from: instruction.byteLength)
            compiledInstructions.append(instruction)
        }
        
        let metaAccounts: [AccountMeta] = messageAccounts.enumerated().map { index, account in
            let meta = AccountMeta(
                publicKey: account,
                signer: index < header.requiredSignatures,
                writable: index < header.requiredSignatures - header.readOnlySigners || index >= header.requiredSignatures && index < messageAccounts.count - header.readOnly,
                payer: index == 0,
                program: false
            )
            
            return meta
        }
        
        let instructions = compiledInstructions.compactMap { $0.decompile(using: metaAccounts) }
        
        guard instructions.count == compiledInstructions.count else {
            print("instruction count mismatch, \(instructions.count) != \(compiledInstructions.count)")
            return nil
        }
        
        self.header = header
        self.accounts = metaAccounts
        self.recentBlockhash = hash
        self.instructions = instructions
    }
    
    public func encode() -> Data {
        var data = Data()
        
        let accounts = accounts.map { $0.publicKey }
        let instructions = instructions.compactMap { $0.compile(using: accounts) }
        
        data.append(header.encode())
        data.append(
            ShortVec.encode(accounts.map { $0.data })
        )
        data.append(recentBlockhash.data)
        data.append(
            ShortVec.encode(instructions.map { $0.encode() })
        )
        
        return data
    }
}
