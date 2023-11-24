//
//  ActionFeePayment.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import CodeAPI

struct ActionFeePayment: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    let cluster: AccountCluster
    let amount: Kin
    
    static let configCountRequirement: Int = 1
    
    init(cluster: AccountCluster, amount: Kin) {
        self.id = 0
        self.signer = cluster.authority.keyPair
        
        self.cluster = cluster
        self.amount = amount
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let configs = serverParameter?.configs else {
            throw Error.missingConfigurations
        }
        
        guard case .feePayment(let destination) = serverParameter?.parameter else {
            throw Error.missingFeeParameter
        }
        
        return configs.map { config in
            TransactionBuilder.transfer(
                timelockDerivedAccounts: cluster.timelockAccounts,
                destination: destination,
                amount: amount,
                nonce: config.nonce,
                recentBlockhash: config.blockhash,
                kreIndex: KRE.index
            )
        }
    }
}

extension ActionFeePayment {
    enum Error: Swift.Error {
        case missingConfigurations
        case missingFeeParameter
    }
}

// MARK: - Proto -

extension ActionFeePayment {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.feePayment = .with {
                $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
                $0.source = cluster.timelockAccounts.vault.publicKey.codeAccountID
                $0.amount = amount.quarks
            }
        }
    }
}
