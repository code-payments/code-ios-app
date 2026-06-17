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
    /// Recipient's owner-authority pubkey. Set on direct contact sends;
    /// `nil` for cash-bill grab settlement.
    let destinationOwner: PublicKey?
    let exchangedFiat: ExchangedFiat
    let verifiedState: VerifiedState
    /// Serialized `flipcash.intent.v1.AppMetadata`. Set on contact DM sends so
    /// the server posts the payment into the chat; `nil` everywhere else.
    let appMetadata: Data?

    var actionGroup: ActionGroup

    init(rendezvous: PublicKey, sourceCluster: AccountCluster, destination: PublicKey, destinationOwner: PublicKey? = nil, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, appMetadata: Data? = nil) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.exchangedFiat    = exchangedFiat
        self.verifiedState    = verifiedState
        self.appMetadata      = appMetadata
        self.destination      = destination
        self.destinationOwner = destinationOwner

        let transfer = ActionTransfer(
            amount: exchangedFiat.onChainAmount,
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

                $0.clientExchangeData = .with {
                    $0.mint = exchangedFiat.mint.solanaAccountID
                    $0.quarks = exchangedFiat.onChainAmount.quarks
                    $0.nativeAmount = exchangedFiat.nativeAmount.doubleValue
                    $0.coreMintFiatExchangeRate = verifiedState.rateProto
                    if let reserveProto = verifiedState.reserveProto {
                        $0.launchpadCurrencyReserveState = reserveProto
                    }
                }

                $0.isWithdrawal = false
                $0.isIndirectSend = false

                if let destinationOwner {
                    $0.destinationOwner = destinationOwner.solanaAccountID
                }
            }

            if let appMetadata {
                $0.appMetadata = .with { $0.value = appMetadata }
            }
        }
    }
}
