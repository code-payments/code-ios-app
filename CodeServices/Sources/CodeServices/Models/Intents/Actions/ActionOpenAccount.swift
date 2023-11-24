//
//  ActionOpenAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionOpenAccount: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    var owner: PublicKey
    var type: AccountType
    var accountCluster: AccountCluster
    
    static let configCountRequirement: Int = 0
    
    init(owner: PublicKey, type: AccountType, accountCluster: AccountCluster) {
        self.id = 0
        self.owner = owner
        self.type = type
        self.accountCluster = accountCluster
    }
    
    func transactions() -> [SolanaTransaction] {
        []
    }
}

// MARK: - Proto -

extension ActionOpenAccount {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.openAccount = .with {
                $0.index = UInt64(accountCluster.index)
                $0.owner = owner.codeAccountID
                $0.accountType = type.accountType
                $0.authority = accountCluster.authority.keyPair.publicKey.codeAccountID
                $0.token = accountCluster.timelockAccounts.vault.publicKey.codeAccountID
                $0.authoritySignature = $0.sign(with: accountCluster.authority.keyPair)
            }
        }
    }
}
