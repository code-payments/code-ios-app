//
//  IntentTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentTransfer: IntentType {
    
    let id: PublicKey
    let sourceCluster: AccountCluster
    let destination: PublicKey
    let exchangedFiat: ExchangedFiat
    let extendedMetadata: Google_Protobuf_Any?
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, sourceCluster: AccountCluster, destination: PublicKey, exchangedFiat: ExchangedFiat, extendedMetadata: Google_Protobuf_Any? = nil) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.exchangedFiat    = exchangedFiat
        self.extendedMetadata = extendedMetadata
        self.destination      = destination
        
        let transfer = ActionTransfer(
            amount: exchangedFiat.usdc,
            sourceCluster: sourceCluster,
            destination: destination
        )
        
        self.actionGroup = ActionGroup(actions: [transfer])
    }
}

// MARK: - Errors -

extension IntentTransfer {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentTransfer {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = destination.solanaAccountID
                $0.exchangeData = .with {
                    $0.quarks       = exchangedFiat.usdc.quarks
                    $0.currency     = exchangedFiat.converted.currencyCode.rawValue
                    $0.exchangeRate = exchangedFiat.rate.fx.doubleValue
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                }
                $0.isWithdrawal = false
                $0.isRemoteSend = false
            }
        }
    }
}
