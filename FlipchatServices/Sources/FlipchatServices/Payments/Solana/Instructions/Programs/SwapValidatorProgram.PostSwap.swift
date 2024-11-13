//
//  TimelockProgram.Initialize.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

extension SwapValidatorProgram {
    public struct PostSwap: Equatable, Hashable, Codable {
        
        public var stateBump: Byte
        public var maxToSend: UInt64
        public var minToReceive: UInt64
        public var preSwapState: PublicKey
        public var source: PublicKey
        public var destination: PublicKey
        public var payer: PublicKey

        init(stateBump: Byte, maxToSend: UInt64, minToReceive: UInt64, preSwapState: PublicKey, source: PublicKey, destination: PublicKey, payer: PublicKey) {
            self.stateBump = stateBump
            self.maxToSend = maxToSend
            self.minToReceive = minToReceive
            self.preSwapState = preSwapState
            self.source = source
            self.destination = destination
            self.payer = payer
        }
    }
}

/// Reference: https://github.com/code-payments/code-server/blob/main/pkg/solana/swapvalidator/instructions_post_swap.go
extension SwapValidatorProgram.PostSwap: InstructionType {
    
    public init(instruction: Instruction) throws {
        var data = try SwapValidatorProgram.parse(.postSwap, instruction: instruction, expectingAccounts: nil) // Dynamic number of accounts
        
        let stateStride = MemoryLayout<Byte>.stride
        
        guard data.canConsume(stateStride), let stateBump = Byte(data: data.consume(stateStride)) else {
            throw ErrorGeneric.unknown
        }
        
        let maxToSendStride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(maxToSendStride), let maxToSend = UInt64(data: data.consume(maxToSendStride)) else {
            throw ErrorGeneric.unknown
        }
        
        let minToReceiveStride = MemoryLayout<UInt64>.stride
        
        guard data.canConsume(minToReceiveStride), let minToReceive = UInt64(data: data.consume(minToReceiveStride)) else {
            throw ErrorGeneric.unknown
        }
        
        self.init(
            stateBump: stateBump,
            maxToSend: maxToSend,
            minToReceive: minToReceive,
            preSwapState: instruction.accounts[0].publicKey,
            source: instruction.accounts[1].publicKey,
            destination: instruction.accounts[2].publicKey,
            payer: instruction.accounts[3].publicKey
        )
    }
    
    public func instruction() -> Instruction {
        Instruction(
            program: SwapValidatorProgram.address,
            accounts: [
                .writable(publicKey: preSwapState),
                .readonly(publicKey: source),
                .readonly(publicKey: destination),
                .writable(publicKey: payer, signer: true),
            ],
            data: encode()
        )
    }
    
    public func encode() -> Data {
        var data = Data()
        
        data.append(contentsOf: SwapValidatorProgram.Command.postSwap.rawValue.bytes)
        data.append(stateBump)
        data.append(contentsOf: maxToSend.bytes)
        data.append(contentsOf: minToReceive.bytes)
        
        return data
    }
}
