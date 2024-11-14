//
//  ActionTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

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
    
    func compactMessages() throws -> [CompactMessage] {
        guard let serverParameter = serverParameter else {
            throw Error.missingServerParameter
        }
        
        return serverParameter.configs.map { config in
            var message = CompactMessage()

            message.append(utf8: "transfer")
            message.append(publicKey: source.vaultPublicKey)
            message.append(publicKey: destination)
            message.append(kin: amount)
            message.append(publicKey: config.nonce)
            message.append(publicKey: config.blockhash)
            
            return message
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
