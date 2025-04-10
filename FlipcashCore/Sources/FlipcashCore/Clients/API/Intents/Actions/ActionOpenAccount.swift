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

    var owner: AccountCluster
    
    static let configCountRequirement: Int = 0
    
    init(owner: AccountCluster) {
        self.id = 0
        self.owner = owner
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
                $0.owner              = owner.authorityPublicKey.codeAccountID
                $0.accountType        = .primary
                $0.authority          = owner.authorityPublicKey.codeAccountID
                $0.token              = owner.vaultPublicKey.codeAccountID
                $0.authoritySignature = $0.sign(with: owner.authority.keyPair)
            }
        }
    }
}
