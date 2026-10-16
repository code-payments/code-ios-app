//
//  IntentMultiTransfer.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashAPI
import SwiftProtobuf

/// Pays two to ten recipients from one source account in a single `SendPublicMultiPayment` intent.
///
/// Emits one `NoPrivacyTransferAction` per payment, in payment order, from the source PRIMARY to
/// the payment's destination. Mirrors `IntentTransfer`, which emits one for `SendPublicPayment`;
/// Android must emit the same actions in the same order.
final class IntentMultiTransfer: IntentType {

    /// One recipient's share of the intent.
    struct Payment {
        /// The recipient's PRIMARY account for the intent's mint.
        let destination: PublicKey
        /// The recipient's owner authority. The server requires it when `destination` (a PRIMARY
        /// account) is auto-opened by this intent; we always send it.
        let destinationOwner: PublicKey
        let exchangedFiat: ExchangedFiat
    }

    enum Error: Swift.Error {
        /// The server accepts two to ten payments.
        case invalidPaymentCount
        /// Every payment must pay the same mint.
        case mintMismatch
        /// Destinations, and their owners, must each be unique, and no destination may be the
        /// source vault.
        case duplicateDestination
        /// A destination owner must differ from the source's owner authority.
        case destinationIsSource
        /// Every payment must use one currency, the verified rate's.
        case currencyMismatch
    }

    static let paymentCountRange = 2...10

    let id: PublicKey
    let sourceCluster: AccountCluster
    let payments: [Payment]
    let mint: PublicKey
    /// The verified rate (and reserve state) every payment is priced against. The server requires
    /// all payments to share currency, rate, and reserve state.
    let verifiedState: VerifiedState
    /// Serialized `flipcash.intent.v1.AppMetadata`, e.g. a chat `reaction_boost`.
    let appMetadata: Data?

    var actionGroup: ActionGroup

    init(rendezvous: PublicKey, sourceCluster: AccountCluster, payments: [Payment], verifiedState: VerifiedState, appMetadata: Data? = nil) throws {
        guard Self.paymentCountRange.contains(payments.count) else {
            throw Error.invalidPaymentCount
        }
        let mint = payments[0].exchangedFiat.mint
        guard payments.allSatisfy({ $0.exchangedFiat.mint == mint }) else {
            throw Error.mintMismatch
        }
        let destinations = payments.map(\.destination) + [sourceCluster.vaultPublicKey]
        guard Set(destinations).count == destinations.count else {
            throw Error.duplicateDestination
        }
        let owners = payments.map(\.destinationOwner)
        guard Set(owners).count == owners.count else {
            throw Error.duplicateDestination
        }
        guard !owners.contains(sourceCluster.authorityPublicKey) else {
            throw Error.destinationIsSource
        }
        let verifiedCurrency = verifiedState.rateProto.exchangeRate.currencyCode.lowercased()
        guard payments.allSatisfy({ $0.exchangedFiat.nativeAmount.currency.rawValue.lowercased() == verifiedCurrency }) else {
            throw Error.currencyMismatch
        }

        self.id            = rendezvous
        self.sourceCluster = sourceCluster
        self.payments      = payments
        self.mint          = mint
        self.verifiedState = verifiedState
        self.appMetadata   = appMetadata

        self.actionGroup = ActionGroup(actions: payments.map {
            ActionTransfer(
                amount: $0.exchangedFiat.onChainAmount,
                sourceCluster: sourceCluster,
                destination: $0.destination,
                mint: mint
            )
        })
    }
}

// MARK: - Proto -

extension IntentMultiTransfer {
    func metadata() -> Ocp_Transaction_V1_Metadata {
        .with {
            $0.sendPublicMultiPayment = .with {
                $0.source = sourceCluster.vaultPublicKey.solanaAccountID
                $0.mint   = mint.solanaAccountID

                $0.payments = payments.map { payment in
                    .with {
                        $0.destination = payment.destination.solanaAccountID
                        $0.destinationOwner = payment.destinationOwner.solanaAccountID
                        $0.clientExchangeData = .with {
                            $0.mint = payment.exchangedFiat.mint.solanaAccountID
                            $0.quarks = payment.exchangedFiat.onChainAmount.quarks
                            $0.nativeAmount = payment.exchangedFiat.nativeAmount.doubleValue
                            $0.coreMintFiatExchangeRate = verifiedState.rateProto
                            if let reserveProto = verifiedState.reserveProto {
                                $0.launchpadCurrencyReserveState = reserveProto
                            }
                        }
                    }
                }
            }

            if let appMetadata {
                $0.appMetadata = .with { $0.value = appMetadata }
            }
        }
    }
}
