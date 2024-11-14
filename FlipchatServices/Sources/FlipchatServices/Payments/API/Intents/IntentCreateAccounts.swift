//
//  IntentCreateAccounts.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

class IntentCreateAccounts: IntentType {
    
    let id: PublicKey
    
    var actionGroup: ActionGroup
    
    private let organizer: Organizer
    
    init(organizer: Organizer) {
        self.id = KeyPair.generate()!.publicKey
        self.organizer = organizer
        self.actionGroup = ActionGroup(actions: organizer.allAccounts().flatMap { type, cluster in
            [
                ActionOpenAccount(
                    owner: organizer.tray.owner.cluster.authority.keyPair.publicKey,
                    type: type,
                    accountCluster: cluster
                )
            ]
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
