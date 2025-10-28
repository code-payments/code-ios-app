//
//  IntentWithdraw.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentWithdraw: IntentType {
    
    let id: PublicKey
    let sourceCluster: AccountCluster
    let fee: Fiat
    let destinationMetadata: DestinationMetadata
    let exchangedFiat: ExchangedFiat
    
    var actionGroup: ActionGroup
    
    init(sourceCluster: AccountCluster, fee: Fiat, destinationMetadata: DestinationMetadata, exchangedFiat: ExchangedFiat) throws {
        self.id                  = PublicKey.generate()!
        self.sourceCluster       = sourceCluster
        self.fee                 = fee
        self.exchangedFiat       = exchangedFiat
        self.destinationMetadata = destinationMetadata
        
        let destination = destinationMetadata.destination.token
//        let fee = destinationMetadata.fee
        
        var group = ActionGroup()
        
        if destinationMetadata.requiresInitialization, fee.quarks > 0 {
            let amountToWithdraw = try exchangedFiat.subtracting(fee: fee)
            group.append(
                ActionTransfer(
                    amount: amountToWithdraw.usdc,
                    sourceCluster: sourceCluster,
                    destination: destination,
                    mint: exchangedFiat.mint
                )
            )
            group.append(
                ActionFeeTransfer(
                    amount: fee,
                    mint: exchangedFiat.mint,
                    sourceCluster: sourceCluster
                )
            )
            
        } else {
            group.append(
                ActionTransfer(
                    amount: exchangedFiat.usdc,
                    sourceCluster: sourceCluster,
                    destination: destination,
                    mint: exchangedFiat.mint
                )
            )
        }
        
        self.actionGroup = group
    }
}

// MARK: - Proto -

extension IntentWithdraw {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = destinationMetadata.destination.token.solanaAccountID
                $0.mint         = exchangedFiat.mint.solanaAccountID
                $0.exchangeData = .with {
                    $0.mint         = exchangedFiat.mint.solanaAccountID
                    $0.quarks       = exchangedFiat.usdc.quarks
                    $0.currency     = exchangedFiat.converted.currencyCode.rawValue
                    $0.exchangeRate = exchangedFiat.rate.fx.doubleValue
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                }
                $0.isWithdrawal = true
                $0.isRemoteSend = false
                
                if let owner = destinationMetadata.destination.owner {
                    $0.destinationOwner = owner.solanaAccountID
                }
            }
        }
    }
}
