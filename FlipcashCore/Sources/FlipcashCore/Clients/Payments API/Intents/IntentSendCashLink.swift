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
    let verifiedState: VerifiedState

    var actionGroup: ActionGroup

    init(rendezvous: PublicKey, sourceCluster: AccountCluster, giftCard: GiftCardCluster, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.giftCard         = giftCard
        self.exchangedFiat    = exchangedFiat
        self.verifiedState    = verifiedState
        
        let openGiftCardAction = ActionOpenAccount(
            kind: .giftCard,
            owner: giftCard.cluster.authorityPublicKey,
            mint: giftCard.mint,
            cluster: giftCard.cluster,
            derivationIndex: 0
        )
        
        let transferAction = ActionTransfer(
            amount: exchangedFiat.underlying,
            sourceCluster: sourceCluster,
            destination: giftCard.cluster.vaultPublicKey,
            mint: exchangedFiat.mint
        )
        
        let autoReturnAction = ActionWithdraw(
            kind: .cashLinkWithdraw(.init(isAutoReturn: true)),
            amount: exchangedFiat.underlying,
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
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = giftCard.cluster.vaultPublicKey.solanaAccountID
                $0.mint         = exchangedFiat.mint.solanaAccountID

                // Use clientExchangeData with embedded proofs for submitting intents
                $0.clientExchangeData = .with {
                    $0.mint = exchangedFiat.mint.solanaAccountID
                    $0.quarks = exchangedFiat.underlying.quarks
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                    $0.coreMintFiatExchangeRate = verifiedState.rateProto
                    if let reserveProto = verifiedState.reserveProto {
                        $0.launchpadCurrencyReserveState = reserveProto
                    }
                }

                $0.isWithdrawal = false
                $0.isRemoteSend = true
            }
        }
    }
}
