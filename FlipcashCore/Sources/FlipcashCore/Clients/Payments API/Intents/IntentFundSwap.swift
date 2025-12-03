//
//  IntentFundSwap.swift
//  FlipcashCore
//
//  Created by Claude.
//  Copyright © 2025 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

/// Intent to fund a VM swap PDA for swap execution
final class IntentFundSwap: IntentType {
    
    let id: PublicKey
    let swapId: SwapId
    let sourceCluster: AccountCluster
    let amount: Quarks
    let fromMint: PublicKey
    let toMint: PublicKey
    
    var actionGroup: ActionGroup
    
    init(
        intentID: PublicKey,
        swapId: SwapId,
        sourceCluster: AccountCluster,
        amount: Quarks,
        fromMint: PublicKey,
        toMint: PublicKey
    ) {
        self.id = intentID
        self.swapId = swapId
        self.sourceCluster = sourceCluster
        self.amount = amount
        self.fromMint = fromMint
        self.toMint = toMint
        
        // Calculate VM swap PDA (this will need proper derivation logic)
        // For now, using swapId as destination - needs proper VM PDA derivation
        let vmSwapDestination = swapId.publicKey
        
        let transfer = ActionTransfer(
            amount: amount,
            sourceCluster: sourceCluster,
            destination: vmSwapDestination,
            mint: fromMint
        )
        
        self.actionGroup = ActionGroup(actions: [transfer])
    }
}

// MARK: - Proto -

extension IntentFundSwap {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            // Use sendPublicPayment metadata for swap funding
            // The server knows this is for swap funding based on the intentID matching the fundingID in StartSwap
            $0.sendPublicPayment = .with {
                $0.source = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination = swapId.publicKey.solanaAccountID // VM swap PDA
                $0.mint = fromMint.solanaAccountID
                $0.exchangeData = .with {
                    $0.mint = fromMint.solanaAccountID
                    $0.quarks = amount.quarks
                    $0.currency = "XXX" // Unknown currency for raw token transfer
                    $0.exchangeRate = 0.0
                    $0.nativeAmount = 0.0
                }
                $0.isWithdrawal = false
                $0.isRemoteSend = false
            }
        }
    }
}
