//
//  ActionTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionTransfer: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?
    
    let kind: Kind
    let intentID: PublicKey
    var amount: Kin
    var source: AccountCluster
    var destination: PublicKey

    static let configCountRequirement: Int = 1
    
    init(kind: Kind, intentID: PublicKey, amount: Kin, source: AccountCluster, destination: PublicKey) {
        self.id = 0
        self.signer = source.authority.keyPair
        
        self.kind = kind
        self.intentID = intentID
        self.amount = amount
        self.source = source
        self.destination = destination
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let serverParameter = serverParameter else {
            throw Error.missingServerParameter
        }
        
        guard let timelock = source.timelock else {
            throw Error.invalidSource
        }
        
        let resolvedDestination: PublicKey
        
        if case .tempPrivacy(let tempPrivacyParameter) = serverParameter.parameter {
            let splitterAccounts = SplitterCommitmentAccounts(
                source: source,
                destination: destination,
                amount: amount,
                treasury: tempPrivacyParameter.treasury,
                recentRoot: tempPrivacyParameter.recentRoot,
                intentID: intentID,
                actionID: id
            )
            
            resolvedDestination = splitterAccounts.vault.publicKey
        } else {
            resolvedDestination = destination
        }
        
        return serverParameter.configs.map { config in
            TransactionBuilder.transfer(
                timelockDerivedAccounts: timelock,
                destination: resolvedDestination,
                amount: amount,
                nonce: config.nonce,
                recentBlockhash: config.blockhash,
                kreIndex: KRE.index
            )
        }
    }
}

extension ActionTransfer {
    enum Error: Swift.Error {
        case missingServerParameter
        case invalidSource
    }
}

// MARK: - Kind -

extension ActionTransfer {
    enum Kind {
        case tempPrivacyTransfer
        case tempPrivacyExchange
        case noPrivacyTransfer
    }
}

// MARK: - Proto -

extension ActionTransfer {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            
            switch kind {
            case .tempPrivacyTransfer:
                $0.temporaryPrivacyTransfer = .with {
                    $0.source = source.vaultPublicKey.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.authority = source.authority.keyPair.publicKey.codeAccountID
                    $0.amount = amount.quarks
                }
                
            case .tempPrivacyExchange:
                $0.temporaryPrivacyExchange = .with {
                    $0.source = source.vaultPublicKey.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.authority = source.authority.keyPair.publicKey.codeAccountID
                    $0.amount = amount.quarks
                }
                
            case .noPrivacyTransfer:
                $0.noPrivacyTransfer = .with {
                    $0.source = source.vaultPublicKey.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.authority = source.authority.keyPair.publicKey.codeAccountID
                    $0.amount = amount.quarks
                }
            }
        }
    }
}
