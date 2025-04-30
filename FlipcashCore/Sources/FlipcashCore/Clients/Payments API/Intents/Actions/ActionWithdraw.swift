//
//  ActionWithdraw.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI

struct ActionWithdraw: ActionType {
    
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

            message.append(utf8: "withdraw_and_close")
            message.append(publicKey: source)
            message.append(publicKey: destination)
            message.append(publicKey: config.nonce)
            message.append(publicKey: config.blockhash)
            
            return message
        }
    }
}

// MARK: - Errors -

extension ActionWithdraw {
    enum Error: Swift.Error {
        case missingServerParameter
    }
}

// MARK: - Kind -

extension ActionWithdraw {
    enum Kind {
        case withdraw
        case cashLinkWithdraw(CashLinkConfiguration)
    }
    
    struct CashLinkConfiguration {
        let isAutoReturn: Bool
    }
}

// MARK: - Proto -

extension ActionWithdraw {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            switch kind {
            case .withdraw:
                $0.noPrivacyWithdraw = .with {
                    $0.authority    = sourceCluster.authorityPublicKey.solanaAccountID
                    $0.source       = source.solanaAccountID
                    $0.destination  = destination.solanaAccountID
                    $0.amount       = amount.quarks
                    $0.shouldClose  = true
                    $0.isAutoReturn = false
                }
                
            case .cashLinkWithdraw(let configuration):
                $0.noPrivacyWithdraw = .with {
                    $0.authority    = sourceCluster.authorityPublicKey.solanaAccountID
                    $0.source       = source.solanaAccountID
                    $0.destination  = destination.solanaAccountID
                    $0.amount       = amount.quarks
                    $0.shouldClose  = true
                    $0.isAutoReturn = configuration.isAutoReturn
                }
            }
        }
    }
}
