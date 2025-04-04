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
    
    let kind: Kind
    let amount: Fiat
    let sourceCluster: AccountCluster
    let source: PublicKey
    let destination: PublicKey

    static let configCountRequirement: Int = 1
    
    init(kind: Kind, amount: Fiat, sourceCluster: AccountCluster, destination: PublicKey) {
        self.id = 0
        self.signer = sourceCluster.authority.keyPair
        
        self.kind          = kind
        self.amount        = amount
        self.sourceCluster = sourceCluster
        self.source        = sourceCluster.vaultPublicKey
        self.destination   = destination
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

// MARK: - Kind -

extension ActionTransfer {
    enum Kind {
        case transfer
        case withdraw
    }
}

// MARK: - Proto -

extension ActionTransfer {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            switch kind {
            case .transfer:
                $0.noPrivacyTransfer = .with {
                    $0.authority   = sourceCluster.authorityPublicKey.codeAccountID
                    $0.source      = source.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.amount      = amount.quarks
                }
                
            case .withdraw:
                $0.noPrivacyWithdraw = .with {
                    $0.authority   = sourceCluster.authorityPublicKey.codeAccountID
                    $0.source      = source.codeAccountID
                    $0.destination = destination.codeAccountID
                    $0.amount      = amount.quarks
                    $0.shouldClose = false
                }
            }
        }
    }
}
