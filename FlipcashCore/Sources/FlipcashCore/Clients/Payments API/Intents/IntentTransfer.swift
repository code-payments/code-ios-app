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
    /// Recipient's owner-authority pubkey. Set only on direct sends to a
    /// resolved contact — `flipcash2-server`'s contact-payment integration
    /// (PR #67) gates the `CONTACT_PAYMENT` push notification on this field
    /// being present, and the OCP server uses it to validate the destination
    /// vault is a Code-managed timelock for that owner. Leave `nil` for
    /// cash-bill grab settlement, where the server already correlates the
    /// destination via the rendezvous handshake state.
    let destinationOwner: PublicKey?
    let exchangedFiat: ExchangedFiat
    let verifiedState: VerifiedState
    let extendedMetadata: Google_Protobuf_Any?

    var actionGroup: ActionGroup

    init(rendezvous: PublicKey, sourceCluster: AccountCluster, destination: PublicKey, destinationOwner: PublicKey? = nil, exchangedFiat: ExchangedFiat, verifiedState: VerifiedState, extendedMetadata: Google_Protobuf_Any? = nil) {
        self.id               = rendezvous
        self.sourceCluster    = sourceCluster
        self.exchangedFiat    = exchangedFiat
        self.verifiedState    = verifiedState
        self.extendedMetadata = extendedMetadata
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

                // Use clientExchangeData with embedded proofs for submitting intents
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
                $0.isRemoteSend = false

                if let destinationOwner {
                    $0.destinationOwner = destinationOwner.solanaAccountID
                }
            }
        }
    }
}
