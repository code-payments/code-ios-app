//
//  TimelockProgram.Initialize.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension SwapValidatorProgram {
    public struct PreSwap: Equatable, Hashable, Codable {
        
        public var preSwapState: PublicKey
        public var user: PublicKey
        public var source: PublicKey
        public var destination: PublicKey
        public var nonce: PublicKey
        public var payer: PublicKey
        public var remainingAccounts: [AccountMeta]

        init(preSwapState: PublicKey, user: PublicKey, source: PublicKey, destination: PublicKey, nonce: PublicKey, payer: PublicKey, remainingAccounts: [AccountMeta]) {
            self.preSwapState = preSwapState
            self.user = user
            self.source = source
            self.destination = destination
            self.nonce = nonce
            self.payer = payer
            self.remainingAccounts = remainingAccounts
        }
    }
}

/// Reference: https://github.com/code-payments/code-server/blob/main/pkg/solana/swapvalidator/instructions_pre_swap.go
extension SwapValidatorProgram.PreSwap: InstructionType {
    
    public init(instruction: Instruction) throws {
        _ = try SwapValidatorProgram.parse(.preSwap, instruction: instruction, expectingAccounts: nil) // Dynamic number of accounts
        
        self.init(
            preSwapState: instruction.accounts[0].publicKey,
            user: instruction.accounts[1].publicKey,
            source: instruction.accounts[2].publicKey,
            destination: instruction.accounts[3].publicKey,
            nonce: instruction.accounts[4].publicKey,
            payer: instruction.accounts[5].publicKey,
            remainingAccounts: Array(instruction.accounts.suffix(from: 6))
        )
    }
    
    public func instruction() -> Instruction {
        var accounts: [AccountMeta] = [
            .writable(publicKey: preSwapState),
            .readonly(publicKey: user),
            .readonly(publicKey: source),
            .readonly(publicKey: destination),
            .readonly(publicKey: nonce),
            .writable(publicKey: payer, signer: true),
            .readonly(publicKey: SystemProgram.address),
            .readonly(publicKey: SysVar.rent.address),
        ]
        
        accounts.append(contentsOf: remainingAccounts)
        
        return Instruction(
            program: SwapValidatorProgram.address,
            accounts: accounts,
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: SwapValidatorProgram.Command.preSwap.rawValue.bytes)
        
        return data
    }
}
