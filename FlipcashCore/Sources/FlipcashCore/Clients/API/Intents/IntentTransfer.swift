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
    
    init(sourceCluster: AccountCluster, destination: PublicKey, exchangedFiat: ExchangedFiat, extendedMetadata: Google_Protobuf_Any? = nil) {
        self.id               = PublicKey.generate()!
        self.sourceCluster    = sourceCluster
        self.exchangedFiat    = exchangedFiat
        self.extendedMetadata = extendedMetadata
        self.destination      = destination
        
        let transfer = ActionTransfer(
            kind: .transfer,
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
                $0.source       = sourceCluster.vaultPublicKey.codeAccountID
                $0.destination  = destination.codeAccountID
                $0.exchangeData = .with {
                    $0.quarks       = exchangedFiat.usdc.quarks
                    $0.currency     = exchangedFiat.converted.currencyCode.rawValue
                    $0.exchangeRate = exchangedFiat.rate.fx.doubleValue
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                }
                $0.isWithdrawal = false
            }
        }
    }
}
