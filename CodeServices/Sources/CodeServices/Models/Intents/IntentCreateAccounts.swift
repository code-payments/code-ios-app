//
//  IntentCreateAccounts.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentCreateAccounts: IntentType {
    
    let id: PublicKey
    
    var actionGroup: ActionGroup
    
    private let organizer: Organizer
    
    init(organizer: Organizer) {
        self.id = KeyPair.generate()!.publicKey
        self.organizer = organizer
        self.actionGroup = ActionGroup(actions: organizer.allAccounts().flatMap { type, cluster in
            var actions: [ActionType] = [
                ActionOpenAccount(
                    owner: organizer.tray.owner.cluster.authority.keyPair.publicKey,
                    type: type,
                    accountCluster: cluster
                )
            ]
            
            if type != .primary {
                actions.append(
                    ActionWithdraw(
                        kind: .closeDormantAccount(type),
                        cluster: cluster,
                        destination: organizer.tray.owner.cluster.timelockAccounts.vault.publicKey
                    )
                )
            }
            
            return actions
        })
    }
}

// MARK: - Proto -

extension IntentCreateAccounts {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.openAccounts = .with { _ in }
        }
    }
}
