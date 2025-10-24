//
//  IntentDistributePoolWinnings.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentDistributePoolWinnings: IntentType {
    
    let id: PublicKey
    let source: AccountCluster
    let distributions: [PoolDistribution]
    
    var actionGroup: ActionGroup
    
    init(source: AccountCluster, distributions: [PoolDistribution]) {
        self.id            = PublicKey.generate()!
        self.source        = source
        self.distributions = distributions
        
        var d = distributions
        let lastDistribution = d.popLast()
        
        var group = ActionGroup()
        
        // All distributions are transfers
        // except the last one in the group
        group.append(contentsOf: d.map {
            ActionTransfer(
                amount: $0.amount,
                sourceCluster: source,
                destination: $0.destination,
                mint: .usdc
            )
        })
        
        // The last action needs to be a withdrawal
        // instead of the conventional transfer
        if let lastDistribution {
            group.append(
                ActionWithdraw(
                    kind: .withdraw,
                    amount: lastDistribution.amount,
                    mint: .usdc,
                    sourceCluster: source,
                    destination: lastDistribution.destination
                )
            )
        }
        
        self.actionGroup = group
    }
}

// MARK: - Proto -

extension IntentDistributePoolWinnings {
    func metadata() -> Code_Transaction_V2_Metadata {
        .with {
            $0.publicDistribution = .with {
                $0.source        = source.vaultPublicKey.solanaAccountID
                $0.distributions = distributions.map { d in
                    .with {
                        $0.quarks      = d.amount.quarks
                        $0.destination = d.destination.solanaAccountID
                    }
                }
            }
        }
    }
}
