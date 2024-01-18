//
//  IntentPublicTransfer.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentPublicTransfer: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let sourceCluster: AccountCluster
    let destination: PublicKey
    let amount: KinAmount
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, source: AccountType, destination: PublicKey, amount: KinAmount) throws {
        self.id = PublicKey.generate()!
        self.organizer = organizer
        self.sourceCluster = organizer.tray.cluster(for: source)
        self.destination = destination
        self.amount = amount
        
        var currentTray = organizer.tray
        
        // 1. Transfer all funds in the primary account
        // directly to the destination. This is a public
        // transfer so no buckets involved and no rotation
        // required.
        
        let transfer = ActionTransfer(
            kind: .noPrivacyTransfer,
            intentID: id,
            amount: amount.kin,
            source: sourceCluster,
            destination: destination
        )
        
        try currentTray.decrement(.primary, kin: amount.kin)
        
        self.actionGroup = ActionGroup(actions: [transfer])
        self.resultTray  = currentTray
    }
}

// MARK: - Errors -

extension IntentPublicTransfer {
    enum Error: Swift.Error {
        case balanceMismatch
    }
}

// MARK: - Proto -

extension IntentPublicTransfer {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source = sourceCluster.timelockAccounts.vault.publicKey.codeAccountID
                $0.destination  = destination.codeAccountID
                $0.isWithdrawal = true
                $0.exchangeData = .with {
                    $0.quarks = amount.kin.quarks
                    $0.currency = amount.rate.currency.rawValue
                    $0.exchangeRate = amount.rate.fx.doubleValue
                    $0.nativeAmount = amount.fiat.doubleValue
                }
            }
        }
    }
}
