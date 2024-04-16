//
//  ActionWithdraw.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionWithdraw: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    let kind: Kind
    let cluster: AccountCluster
    let destination: PublicKey
    let tipAccount: TipAccount?
    let legacy: Bool
    
    static let configCountRequirement: Int = 1
    
    init(kind: Kind, cluster: AccountCluster, destination: PublicKey, tipAccount: TipAccount? = nil, legacy: Bool = false) {
        self.id = 0
        self.signer = cluster.authority.keyPair
        
        self.kind = kind
        self.cluster = cluster
        self.destination = destination
        self.tipAccount = tipAccount
        self.legacy = legacy
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let configs = serverParameter?.configs else {
            throw Error.missingConfigurations
        }
        
        guard let timelock = cluster.timelock else {
            throw Error.invalidTimelockAccounts
        }
        
        return configs.map { config in
            TransactionBuilder.closeDormantAccount(
                authority: cluster.authority.keyPair.publicKey,
                timelockDerivedAccounts: timelock,
                destination: destination,
                nonce: config.nonce,
                recentBlockhash: config.blockhash,
                kreIndex: KRE.index,
                tipAccount: tipAccount,
                legacy: legacy
            )
        }
    }
}

extension ActionWithdraw {
    enum Error: Swift.Error {
        case missingConfigurations
        case invalidTimelockAccounts
    }
}

// MARK: - Kind -

extension ActionWithdraw {
    enum Kind: Equatable {
        case closeDormantAccount(AccountType)
        case noPrivacyWithdraw(Kin)
    }
}

// MARK: - Proto -

extension ActionWithdraw {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            switch kind {
            case .closeDormantAccount(let type):
                $0.closeDormantAccount = .with {
                    $0.accountType = type.accountType
                    $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
                    $0.token = cluster.vaultPublicKey.codeAccountID
                    $0.destination = destination.codeAccountID
                }
                
            case .noPrivacyWithdraw(let amount):
                $0.noPrivacyWithdraw = .with {
                    $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
                    $0.source = cluster.vaultPublicKey.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.amount = amount.quarks
                    $0.shouldClose = true
                }
            }
        }
    }
}
