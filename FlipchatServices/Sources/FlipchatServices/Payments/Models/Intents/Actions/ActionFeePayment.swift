//
//  ActionFeePayment.swift
//  FlipchatServices
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

    let kind: Kind
    let cluster: AccountCluster
    let amount: Kin
    
    static let configCountRequirement: Int = 1
    
    init(kind: Kind, cluster: AccountCluster, amount: Kin) {
        self.id = 0
        self.signer = cluster.authority.keyPair
        
        self.kind = kind
        self.cluster = cluster
        self.amount = amount
    }
    
    func transactions() throws -> [SolanaTransaction] {
        guard let configs = serverParameter?.configs else {
            throw Error.missingConfigurations
        }
        
        
        
        guard let timelock = cluster.timelock else {
            throw Error.invalidTimelockAccounts
        }
        
        let destination: PublicKey
        
        switch kind {
        case .code:
            guard case .feePayment(let d) = serverParameter?.parameter, let feeDestination = d else {
                throw Error.missingFeeParameter
            }
            
            destination = feeDestination
            
        case .thirdParty(let publicKey):
            destination = publicKey
        }
        
        return configs.map { config in
            TransactionBuilder.transfer(
                timelockDerivedAccounts: timelock,
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
    enum Kind {
        case code
        case thirdParty(PublicKey)
    }
}

extension ActionFeePayment {
    enum Error: Swift.Error {
        case missingConfigurations
        case missingFeeParameter
        case missingFeeDestination
        case invalidTimelockAccounts
    }
}

// MARK: - Proto -

extension ActionFeePayment {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.feePayment = .with {
                $0.type = kind.codeType
                $0.authority = cluster.authority.keyPair.publicKey.codeAccountID
                $0.source = cluster.vaultPublicKey.codeAccountID
                $0.amount = amount.quarks
                
                if case .thirdParty(let destination) = kind {
                    $0.destination = destination.codeAccountID
                }
            }
        }
    }
}

private extension ActionFeePayment.Kind {
    var codeType: Code_Transaction_V2_FeePaymentAction.FeeType {
        switch self {
        case .code:       return .code
        case .thirdParty: return .thirdParty
        }
    }
}
