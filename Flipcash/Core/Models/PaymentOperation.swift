//
//  PaymentOperation.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-14.
//

import Foundation
import FlipcashCore

/// Funding-time payload shared by buy-existing and launch-new-currency flows.
/// `PurchaseMethodSheet` and the per-funding-path coordinators (`PhantomCoordinator`,
/// `OnrampCoordinator`) accept this so the picker UI is identical regardless
/// of what the user is funding.
///
/// Marked `nonisolated` so the type and its computed-property unwraps are
/// reachable from `AppRouter.Destination` (which is itself `nonisolated` for
/// cross-actor logging metadata).
nonisolated enum PaymentOperation: Hashable, Sendable, Identifiable {

    case buy(BuyPayload)
    case launch(LaunchPayload)

    struct BuyPayload: Hashable, Sendable {
        let id: UUID
        let mint: PublicKey
        let currencyName: String
        let amount: ExchangedFiat
        let verifiedState: VerifiedState

        init(mint: PublicKey, currencyName: String, amount: ExchangedFiat, verifiedState: VerifiedState) {
            self.id = UUID()
            self.mint = mint
            self.currencyName = currencyName
            self.amount = amount
            self.verifiedState = verifiedState
        }
    }

    struct LaunchPayload: Hashable, Sendable {
        let id: UUID
        let currencyName: String
        let total: ExchangedFiat
        let launchAmount: ExchangedFiat
        let launchFee: ExchangedFiat

        init(currencyName: String, total: ExchangedFiat, launchAmount: ExchangedFiat, launchFee: ExchangedFiat) {
            self.id = UUID()
            self.currencyName = currencyName
            self.total = total
            self.launchAmount = launchAmount
            self.launchFee = launchFee
        }
    }

    var id: UUID {
        switch self {
        case .buy(let payload):    return payload.id
        case .launch(let payload): return payload.id
        }
    }

    /// Amount displayed on the picker / funding screens. For buy this is the
    /// purchase amount; for launch this is the total (purchase + fee).
    var displayAmount: ExchangedFiat {
        switch self {
        case .buy(let payload):    return payload.amount
        case .launch(let payload): return payload.total
        }
    }

    var currencyName: String {
        switch self {
        case .buy(let payload):    return payload.currencyName
        case .launch(let payload): return payload.currencyName
        }
    }
}
