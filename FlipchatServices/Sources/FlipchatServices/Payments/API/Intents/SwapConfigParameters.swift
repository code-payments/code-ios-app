//
//  SwapConfigParameters.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

struct SwapConfigParameters {
    
    let payer: PublicKey
    let swapProgram: PublicKey
    let nonce: PublicKey
    let blockhash: Hash
    let maxToSend: UInt64
    let minToReceive: UInt64
    let computeUnitLimit: UInt32
    let computeUnitPrice: UInt64
    let swapAccounts: [AccountMeta]
    let swapData: Data
    
    init(payer: PublicKey, swapProgram: PublicKey, nonce: PublicKey, blockhash: Hash, maxToSend: UInt64, minToReceive: UInt64, computeUnitLimit: UInt32, computeUnitPrice: UInt64, swapAccounts: [AccountMeta], swapData: Data) {
        self.payer = payer
        self.swapProgram = swapProgram
        self.nonce = nonce
        self.blockhash = blockhash
        self.maxToSend = maxToSend
        self.minToReceive = minToReceive
        self.computeUnitLimit = computeUnitLimit
        self.computeUnitPrice = computeUnitPrice
        self.swapAccounts = swapAccounts
        self.swapData = swapData
    }
}

// MARK: - Error -

extension SwapConfigParameters {
    enum Error: Swift.Error {
        case deserializationFailed
    }
}

// MARK: - Proto -

extension SwapConfigParameters {
    init(_ proto: Code_Transaction_V2_SwapResponse.ServerParameters) throws {
        guard
            let payer = PublicKey(proto.payer.value),
            let swapProgram = PublicKey(proto.swapProgram.value),
            let nonce = PublicKey(proto.nonce.value),
            let blockhash = Hash(proto.recentBlockhash.value)
        else {
            throw Error.deserializationFailed
        }
        
        self.init(
            payer: payer,
            swapProgram: swapProgram,
            nonce: nonce,
            blockhash: blockhash,
            maxToSend: proto.maxToSend,
            minToReceive: proto.minToReceive,
            computeUnitLimit: proto.computeUnitLimit,
            computeUnitPrice: proto.computeUnitPrice,
            swapAccounts: try proto.swapIxnAccounts.map { try AccountMeta($0) },
            swapData: proto.swapIxnData
        )
    }
}

extension AccountMeta {
    init(_ proto: Code_Common_V1_InstructionAccount) throws {
        guard
            let publicKey = PublicKey(proto.account.value)
        else {
            throw SwapConfigParameters.Error.deserializationFailed
        }
        
        self.init(
            publicKey: publicKey,
            signer: proto.isSigner,
            writable: proto.isWritable,
            payer: false,
            program: false
        )
    }
}
