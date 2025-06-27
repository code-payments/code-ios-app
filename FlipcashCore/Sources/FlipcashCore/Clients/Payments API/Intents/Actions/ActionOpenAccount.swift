//
//  ActionOpenAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

struct ActionOpenAccount: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    let kind: AccountKind
    let cluster: AccountCluster
    
    static let configCountRequirement: Int = 0
    
    init(kind: AccountKind, cluster: AccountCluster) {
        self.id      = 0
        self.kind    = kind
        self.cluster = cluster
    }
    
    func compactMessages() throws -> [CompactMessage] {
        []
    }
}

// MARK: - Proto -

extension ActionOpenAccount {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.openAccount = .with {
                $0.index              = 0
                $0.owner              = cluster.authorityPublicKey.solanaAccountID
                $0.accountType        = kind.proto
                $0.authority          = cluster.authorityPublicKey.solanaAccountID
                $0.token              = cluster.vaultPublicKey.solanaAccountID
                $0.authoritySignature = $0.sign(with: cluster.authority.keyPair)
            }
        }
    }
}

extension AccountKind {
    var proto: Code_Common_V1_AccountType {
        switch self {
        case .primary:  return .primary
        case .giftCard: return .remoteSendGiftCard
        case .pool:     return .pool
        }
    }
}
