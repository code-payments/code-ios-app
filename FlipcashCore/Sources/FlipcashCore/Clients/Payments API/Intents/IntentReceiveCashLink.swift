//
//  IntentReceiveCashLink.swift
//  FlipcashCore
//
//  Created by Dima Bart on 2025-04-30.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentReceiveCashLink: IntentType {
    let id: PublicKey
    let ownerCluster: AccountCluster
    let giftCard: GiftCardCluster
    let usdf: Quarks
    
    var actionGroup: ActionGroup
    
    init(ownerCluster: AccountCluster, giftCard: GiftCardCluster, usdf: Quarks) {
        self.id           = PublicKey.generate()!
        self.ownerCluster = ownerCluster
        self.giftCard     = giftCard
        self.usdf         = usdf
        
        self.actionGroup = ActionGroup(actions: [
            ActionWithdraw(
                kind: .cashLinkWithdraw(.init(isAutoReturn: false)),
                amount: usdf,
                mint: giftCard.mint,
                sourceCluster: giftCard.cluster,
                destination: ownerCluster.vaultPublicKey
            )
        ])
    }
}

// MARK: - Proto -

extension IntentReceiveCashLink {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.receivePaymentsPublicly = .with {
                $0.source       = giftCard.cluster.vaultPublicKey.solanaAccountID
                $0.quarks       = usdf.quarks
                $0.mint         = giftCard.mint.solanaAccountID
                $0.isRemoteSend = true
            }
        }
    }
}
