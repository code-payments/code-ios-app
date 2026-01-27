//
//  IntentWithdraw.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentWithdraw: IntentType {

    let id: PublicKey
    let sourceCluster: AccountCluster
    let fee: Quarks
    let destinationMetadata: DestinationMetadata
    let exchangedFiat: ExchangedFiat
    let verifiedState: VerifiedState

    var actionGroup: ActionGroup

    init(sourceCluster: AccountCluster, fee: Quarks, destinationMetadata: DestinationMetadata, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState) throws {
        self.id                  = PublicKey.generate()!
        self.sourceCluster       = sourceCluster
        self.fee                 = fee
        self.exchangedFiat       = exchangedFiat
        self.verifiedState       = verifiedState
        self.destinationMetadata = destinationMetadata
        
        let destination = destinationMetadata.destination.token
//        let fee = destinationMetadata.fee
        
        var group = ActionGroup()
        
        if destinationMetadata.requiresInitialization, fee.quarks > 0 {
            let amountToWithdraw = try exchangedFiat.subtracting(fee: fee)
            group.append(
                ActionTransfer(
                    amount: amountToWithdraw.underlying,
                    sourceCluster: sourceCluster,
                    destination: destination,
                    mint: exchangedFiat.mint
                )
            )
            group.append(
                ActionFeeTransfer(
                    amount: fee,
                    mint: exchangedFiat.mint,
                    sourceCluster: sourceCluster
                )
            )
            
        } else {
            group.append(
                ActionTransfer(
                    amount: exchangedFiat.underlying,
                    sourceCluster: sourceCluster,
                    destination: destination,
                    mint: exchangedFiat.mint
                )
            )
        }
        
        self.actionGroup = group
    }
}

// MARK: - Proto -

extension IntentWithdraw {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = destinationMetadata.destination.token.solanaAccountID
                $0.mint         = exchangedFiat.mint.solanaAccountID

                // Use clientExchangeData with embedded proofs for submitting intents
                $0.clientExchangeData = .with {
                    $0.mint = exchangedFiat.mint.solanaAccountID
                    $0.quarks = exchangedFiat.underlying.quarks
                    $0.nativeAmount = exchangedFiat.converted.doubleValue
                    $0.coreMintFiatExchangeRate = verifiedState.rateProto
                    if let reserveProto = verifiedState.reserveProto {
                        $0.launchpadCurrencyReserveState = reserveProto
                    }
                }

                $0.isWithdrawal = true
                $0.isRemoteSend = false

                if let owner = destinationMetadata.destination.owner {
                    $0.destinationOwner = owner.solanaAccountID
                }
            }
        }
    }
}
