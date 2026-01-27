//
//  IntentTransfer.swift
//  FlipchatServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

final class IntentTransfer: IntentType {

    let id: PublicKey
    let sourceCluster: AccountCluster
    let destination: PublicKey
    let exchangedFiat: ExchangedFiat
    let verifiedState: VerifiedState
    let extendedMetadata: Google_Protobuf_Any?

    var actionGroup: ActionGroup

    init(rendezvous: PublicKey, sourceCluster: AccountCluster, destination: PublicKey, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, extendedMetadata: Google_Protobuf_Any? = nil) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.exchangedFiat    = exchangedFiat
        self.verifiedState    = verifiedState
        self.extendedMetadata = extendedMetadata
        self.destination      = destination

        let transfer = ActionTransfer(
            amount: exchangedFiat.underlying,
            sourceCluster: sourceCluster,
            destination: destination,
            mint: exchangedFiat.mint
        )

        self.actionGroup = ActionGroup(actions: [transfer])
    }
}

// MARK: - Proto -

extension IntentTransfer {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.sendPublicPayment = .with {
                $0.source       = sourceCluster.vaultPublicKey.solanaAccountID
                $0.destination  = destination.solanaAccountID
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

                $0.isWithdrawal = false
                $0.isRemoteSend = false
            }
        }
    }
}
