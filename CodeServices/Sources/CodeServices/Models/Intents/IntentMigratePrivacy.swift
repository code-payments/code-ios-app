//
//  IntentMigratePrivacy.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentMigratePrivacy: IntentType {
    
    let id: PublicKey
    let organizer: Organizer
    let amount: Kin
    
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, amount: Kin) {
        let intentID = PublicKey.generate()!
        
        self.id = intentID
        self.organizer = organizer
        self.amount = amount
        
        let legacyCluster = AccountCluster(
            authority: .derive(using: .solana, mnemonic: organizer.mnemonic),
            legacy: true
        )
        
        var tray = organizer.tray
        var group = ActionGroup()
        
        if amount.quarks > 0 {
            
            // If there's a balance in the legacy account
            // we'll move the funds over to a new private
            // primary account
            group.append(
                ActionWithdraw(
                    kind: .noPrivacyWithdraw(amount),
                    cluster: legacyCluster,
                    destination: organizer.primaryVault,
                    legacy: true
                )
            )
            tray.increment(.primary, kin: amount)
            
        } else {
            
            // If there's no balance, we can
            // simply close the account
            group.append(
                ActionCloseEmptyAccount(
                    type: .primary,
                    cluster: legacyCluster,
                    legacy: true
                )
            )
        }
        
        self.actionGroup = group
        self.resultTray = tray
    }
}

// MARK: - Proto -

extension IntentMigratePrivacy {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.migrateToPrivacy2022 = .with {
                $0.quarks = amount.quarks
            }
        }
    }
}
