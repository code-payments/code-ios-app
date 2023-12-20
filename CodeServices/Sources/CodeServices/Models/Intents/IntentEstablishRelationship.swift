//
//  IntentEstablishRelationship.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

class IntentEstablishRelationship: IntentType {
    
    let id: PublicKey
    let domain: Domain
    let resultTray: Tray
    
    var actionGroup: ActionGroup
    
    init(organizer: Organizer, domain: Domain) {
        self.id = PublicKey.generate()!
        self.domain = domain
        
        var currentTray = organizer.tray
        let relationship = currentTray.createRelationship(for: domain)
        
        let openAccount = ActionOpenAccount(
            owner: currentTray.owner.cluster.authority.keyPair.publicKey,
            type: .relationship(domain),
            accountCluster: relationship.cluster
        )
        
        self.actionGroup = ActionGroup(actions: [openAccount])
        self.resultTray  = currentTray
    }
}

// MARK: - Proto -

extension IntentEstablishRelationship {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.establishRelationship = .with {
                $0.relationship = .with {
                    $0.domain = .with { $0.value = domain.relationshipHost }
                }
            }
        }
    }
}
