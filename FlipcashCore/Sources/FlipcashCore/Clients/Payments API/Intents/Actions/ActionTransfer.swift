//
//  ActionTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

struct ActionTransfer: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?
    
    let amount: Quarks
    let sourceCluster: AccountCluster
    let source: PublicKey
    let destination: PublicKey
    let mint: PublicKey

    static let configCountRequirement: Int = 1
    
    init(amount: Quarks, sourceCluster: AccountCluster, destination: PublicKey, mint: PublicKey) {
        self.id = 0
        self.signer = sourceCluster.authority.keyPair
        
        self.amount        = amount
        self.sourceCluster = sourceCluster
        self.source        = sourceCluster.vaultPublicKey
        self.destination   = destination
        self.mint          = mint
    }
    
    func compactMessages() throws -> [CompactMessage] {
        guard let serverParameter = serverParameter else {
            throw Error.missingServerParameter
        }
        
        return serverParameter.configs.map { config in
            var message = CompactMessage()

            message.append(utf8: "transfer")
            message.append(publicKey: source)
            message.append(publicKey: destination)
            message.append(fiat: amount)
            message.append(publicKey: config.nonce)
            message.append(publicKey: config.blockhash)
            
            return message
        }
    }
}

// MARK: - Errors -

extension ActionTransfer {
    enum Error: Swift.Error {
        case missingServerParameter
    }
}

// MARK: - Proto -

extension ActionTransfer {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            $0.noPrivacyTransfer = .with {
                $0.mint        = mint.solanaAccountID
                $0.authority   = sourceCluster.authorityPublicKey.solanaAccountID
                $0.source      = source.solanaAccountID
                $0.destination = destination.solanaAccountID
                $0.amount      = amount.quarks
            }
        }
    }
}
