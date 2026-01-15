//
//  ActionFeeTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

struct ActionFeeTransfer: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?
    
    let amount: Quarks
    let mint: PublicKey
    let sourceCluster: AccountCluster
    let source: PublicKey

    static let configCountRequirement: Int = 1
    
    init(amount: Quarks, mint: PublicKey, sourceCluster: AccountCluster) {
        self.id = 0
        self.signer = sourceCluster.authority.keyPair
        
        self.amount        = amount
        self.mint          = mint
        self.sourceCluster = sourceCluster
        self.source        = sourceCluster.vaultPublicKey
    }
    
    func compactMessages() throws -> [CompactMessage] {
        guard let serverParameter = serverParameter else {
            throw Error.missingServerParameter
        }
        
        guard case .feePayment(let feeDestination) = serverParameter.parameter else {
            throw Error.missingFeeDestination
        }
        
        return serverParameter.configs.map { config in
            var message = CompactMessage()

            message.append(utf8: "transfer")
            message.append(publicKey: source)
            message.append(publicKey: feeDestination)
            message.append(fiat: amount)
            message.append(publicKey: config.nonce)
            message.append(publicKey: config.blockhash)
            
            return message
        }
    }
}

// MARK: - Errors -

extension ActionFeeTransfer {
    enum Error: Swift.Error {
        case missingServerParameter
        case missingFeeDestination
    }
}

// MARK: - Proto -

extension ActionFeeTransfer {
    func action() -> Ocp_Transaction_V1_Action {
        .with {
            $0.id = UInt32(id)
            $0.feePayment = .with {
                $0.type        = .createOnSendWithdrawal
                $0.authority   = sourceCluster.authorityPublicKey.solanaAccountID
                $0.source      = source.solanaAccountID
                $0.amount      = amount.quarks
                $0.mint        = mint.solanaAccountID
            }
        }
    }
}
