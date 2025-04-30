//
//  IntentCreateAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

final class IntentCreateAccount: IntentType {
    
    let id: PublicKey
    let owner: AccountCluster
    
    var actionGroup: ActionGroup
    
    init(owner: AccountCluster) {
        self.id = PublicKey.generate()!
        self.owner = owner
        
        self.actionGroup = ActionGroup(actions: [
            ActionOpenAccount(
                kind: .primary,
                cluster: owner
            )
        ])
    }
}

// MARK: - Proto -

extension IntentCreateAccount {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.openAccounts = .with { _ in }
        }
    }
}
