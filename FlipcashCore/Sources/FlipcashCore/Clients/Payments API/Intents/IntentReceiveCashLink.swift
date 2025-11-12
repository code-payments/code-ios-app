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
    let usdc: Quarks
    
    var actionGroup: ActionGroup
    
    init(ownerCluster: AccountCluster, giftCard: GiftCardCluster, usdc: Quarks) {
        self.id           = PublicKey.generate()!
        self.ownerCluster = ownerCluster
        self.giftCard     = giftCard
        self.usdc         = usdc
        
        self.actionGroup = ActionGroup(actions: [
            ActionWithdraw(
                kind: .cashLinkWithdraw(.init(isAutoReturn: false)),
                amount: usdc,
                mint: giftCard.mint,
                sourceCluster: giftCard.cluster,
                destination: ownerCluster.vaultPublicKey
            )
        ])
    }
}

// MARK: - Proto -

extension IntentReceiveCashLink {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.receivePaymentsPublicly = .with {
                $0.source       = giftCard.cluster.vaultPublicKey.solanaAccountID
                $0.quarks       = usdc.quarks
                $0.mint         = giftCard.mint.solanaAccountID
                $0.isRemoteSend = true
            }
        }
    }
}
