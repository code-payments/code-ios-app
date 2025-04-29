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

final class IntentCashLink: IntentType {
    
    let id: PublicKey
    let sourceCluster: AccountCluster
    let giftCard: GiftCardCluster
    let exchangedFiat: ExchangedFiat
    let extendedMetadata: Google_Protobuf_Any?
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, sourceCluster: AccountCluster, giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat, extendedMetadata: Google_Protobuf_Any? = nil) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.giftCard         = giftCard
        self.exchangedFiat    = exchangedFiat
        self.extendedMetadata = extendedMetadata
        
        let openGiftCardAction = ActionOpenAccount(
            owner: giftCard.cluster
        )
        
        let transferAction = ActionTransfer(
            kind: .cashLink(.init(isAutoReturn: false)),
            amount: exchangedFiat.usdc,
            sourceCluster: sourceCluster,
            destination: giftCard.cluster.vaultPublicKey
        )
        
        let autoReturnAction = ActionTransfer(
            kind: .cashLink(.init(isAutoReturn: true)),
            amount: exchangedFiat.usdc,
            sourceCluster: giftCard.cluster,
            destination: sourceCluster.vaultPublicKey
        )
        
        self.actionGroup = ActionGroup(actions: [
            openGiftCardAction,
            transferAction,
            autoReturnAction,
        ])
    }
}

// MARK: - Errors -

extension IntentCashLink {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentCashLink {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = giftCard.cluster.vaultPublicKey.solanaAccountID
                $0.exchangeData = .with {
                    $0.quarks       = exchangedFiat.usdc.quarks
                    $0.currency     = exchangedFiat.converted.currencyCode.rawValue
                    $0.exchangeRate = exchangedFiat.rate.fx.doubleValue
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                }
                $0.isWithdrawal = false
                $0.isRemoteSend = true
            }
        }
    }
}
