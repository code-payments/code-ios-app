//
//  ActionWithdraw.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipchatPaymentsAPI

struct ActionWithdraw: ActionType {
    
    var id: Int
    var serverParameter: ServerParameter?
    var signer: KeyPair?

    let kind: Kind
    let cluster: AccountCluster
    let destination: PublicKey
    
    static let configCountRequirement: Int = 1
    
    init(kind: Kind, cluster: AccountCluster, destination: PublicKey) {
        self.id = 0
        self.signer = cluster.authority.keyPair
        
        self.kind = kind
        self.cluster = cluster
        self.destination = destination
    }
    
    func compactMessages() throws -> [CompactMessage] {
        guard let serverParameter = serverParameter else {
            throw Error.missingConfigurations
        }
        
        return []
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
        case noPrivacyWithdraw(Kin)
    }
}

// MARK: - Proto -

extension ActionWithdraw {
    func action() -> Code_Transaction_V2_Action {
        .with {
            $0.id = UInt32(id)
            switch kind {
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
