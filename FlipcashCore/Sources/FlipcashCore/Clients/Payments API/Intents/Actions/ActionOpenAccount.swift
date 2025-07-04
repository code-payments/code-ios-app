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
    let owner: PublicKey
    let cluster: AccountCluster
    let derivationIndex: Int
    
    static let configCountRequirement: Int = 0
    
    init(kind: AccountKind, owner: PublicKey, cluster: AccountCluster, derivationIndex: Int) {
        self.id              = 0
        self.kind            = kind
        self.owner           = owner
        self.cluster         = cluster
        self.derivationIndex = derivationIndex
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
                $0.index              = UInt64(derivationIndex)
                $0.owner              = owner.solanaAccountID
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
