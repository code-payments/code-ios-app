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
    let owner: PublicKey
    let mint: PublicKey
    let cluster: AccountCluster
    let kind: AccountKind
    let derivationIndex: Int
    
    var actionGroup: ActionGroup
    
    init(owner: PublicKey, mint: PublicKey, cluster: AccountCluster, kind: AccountKind, derivationIndex: Int) {
        self.id              = PublicKey.generate()!
        self.owner           = owner
        self.mint            = mint
        self.cluster         = cluster
        self.kind            = kind
        self.derivationIndex = derivationIndex
        
        self.actionGroup = ActionGroup(actions: [
            ActionOpenAccount(
                kind: kind,
                owner: owner,
                mint: mint,
                cluster: cluster,
                derivationIndex: derivationIndex
            )
        ])
    }
}

public enum AccountKind {
    case primary
    case giftCard
    case pool
}

// MARK: - Proto -

extension IntentCreateAccount {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.openAccounts = .with {
                switch kind {
                case .primary, .giftCard:
                    $0.accountSet = .user
                case .pool:
                    $0.accountSet = .pool
                }
                $0.mint = mint.solanaAccountID
            }
        }
    }
}
