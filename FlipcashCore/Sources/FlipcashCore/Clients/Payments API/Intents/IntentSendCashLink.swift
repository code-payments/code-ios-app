//
//  IntentSendCashLink.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentSendCashLink: IntentType {
    
    let id: PublicKey
    let sourceCluster: AccountCluster
    let giftCard: GiftCardCluster
    let exchangedFiat: ExchangedFiat
    
    var actionGroup: ActionGroup
    
    init(rendezvous: PublicKey, sourceCluster: AccountCluster, giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.giftCard         = giftCard
        self.exchangedFiat    = exchangedFiat
        
        let openGiftCardAction = ActionOpenAccount(
            kind: .giftCard,
            owner: giftCard.cluster.authorityPublicKey,
            mint: giftCard.mint,
            cluster: giftCard.cluster,
            derivationIndex: 0
        )
        
        let transferAction = ActionTransfer(
            amount: exchangedFiat.usdc,
            sourceCluster: sourceCluster,
            destination: giftCard.cluster.vaultPublicKey,
            mint: exchangedFiat.mint
        )
        
        let autoReturnAction = ActionWithdraw(
            kind: .cashLinkWithdraw(.init(isAutoReturn: true)),
            amount: exchangedFiat.usdc,
            mint: giftCard.mint,
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

// MARK: - Proto -

extension IntentSendCashLink {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = giftCard.cluster.vaultPublicKey.solanaAccountID
                $0.mint         = exchangedFiat.mint.solanaAccountID
                $0.exchangeData = .with {
                    $0.mint         = exchangedFiat.mint.solanaAccountID
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
