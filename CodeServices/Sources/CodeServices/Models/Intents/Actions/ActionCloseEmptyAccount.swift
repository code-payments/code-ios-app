//
//  ActionCloseEmptyAccount.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionCloseEmptyAccount: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    let type: AccountType
    let cluster: AccountCluster
    
    static let configCountRequirement: Int = 1
    
    init(type: AccountType, cluster: AccountCluster) {
        self.id = 0
        self.signer = cluster.authority.keyPair
        
        self.type = type
        self.cluster = cluster
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let configs = serverParameter?.configs else {
            throw Error.missingConfigurations
        }
        
        guard let timelock = cluster.timelock else {
            throw Error.invalidTimelockAccounts
        }
        
        return configs.map { config in
            TransactionBuilder.closeEmptyAccount(
                timelockDerivedAccounts: timelock,
                maxDustAmount: 1,
                nonce: config.nonce,
                recentBlockhash: config.blockhash
            )
        }
    }
}

extension ActionCloseEmptyAccount {
    enum Error: Swift.Error {
        case missingConfigurations
        case invalidTimelockAccounts
    }
}

// MARK: - Proto -

extension ActionCloseEmptyAccount {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.closeEmptyAccount = .with {
                $0.accountType = type.accountType
                $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
                $0.token = cluster.vaultPublicKey.codeAccountID
            }
        }
    }
}
