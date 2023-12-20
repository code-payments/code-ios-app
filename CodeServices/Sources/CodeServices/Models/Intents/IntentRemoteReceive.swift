//
//  IntentRemoteReceive.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentRemoteReceive: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let giftCard: GiftCardAccount
    let amount: Kin
    let isVoidingGiftCard: Bool
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, giftCard: GiftCardAccount, amount: Kin, isVoidingGiftCard: Bool) throws {
        self.id = PublicKey.generate()!
        self.organizer = organizer
        self.giftCard = giftCard
        self.amount = amount
        self.isVoidingGiftCard = isVoidingGiftCard
        
        var currentTray = organizer.tray
        let startBalance = currentTray.availableBalance
        
        let giftCardWithdraw = ActionWithdraw(
            kind: .noPrivacyWithdraw(amount),
            cluster: giftCard.cluster,
            destination: organizer.incomingVault
        )
        
        try currentTray.increment(.incoming, kin: amount)
        
        let endBalance = currentTray.availableBalance
        
        guard endBalance - startBalance == amount else {
            throw Error.balanceMismatch
        }
        
        self.actionGroup = ActionGroup(actions: [giftCardWithdraw])
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentRemoteReceive {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentRemoteReceive {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.receivePaymentsPublicly = .with {
                $0.source = giftCard.cluster.timelockAccounts.vault.publicKey.codeAccountID
                $0.quarks = amount.quarks
                $0.isRemoteSend = true
                $0.isIssuerVoidingGiftCard = isVoidingGiftCard
            }
        }
    }
}
