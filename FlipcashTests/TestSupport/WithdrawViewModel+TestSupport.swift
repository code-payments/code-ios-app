//
//  WithdrawViewModel+TestSupport.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-02-27.
//

import Foundation
import SwiftUI
import FlipcashCore
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

@MainActor
enum WithdrawViewModelTestHelpers {

    static func createViewModel(
        entryCurrency: CurrencyCode = .usd,
        rates: [Rate] = [.oneToOne]
    ) -> WithdrawViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock

        sessionContainer.ratesController.configureTestRates(
            entryCurrency: entryCurrency,
            rates: rates
        )

        return WithdrawViewModel(
            isPresented: .constant(true),
            container: container,
            sessionContainer: sessionContainer
        )
    }

    static func createExchangedBalance(
        mint: PublicKey = .usdf,
        quarks: UInt64 = 10_000_000
    ) -> ExchangedBalance {
        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: "USDF",
            name: "USDF Coin",
            supplyFromBonding: nil,
            sellFeeBps: nil,
            mint: mint,
            vmAuthority: nil,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )

        return ExchangedBalance(
            stored: stored,
            exchangedFiat: ExchangedFiat.computeFromQuarks(
                quarks: quarks,
                mint: mint,
                rate: .oneToOne,
                supplyQuarks: nil
            )
        )
    }

    static func createDestinationMetadata(
        requiresInitialization: Bool = false,
        fee: Quarks = Quarks(quarks: 0 as UInt64, currencyCode: .usd, decimals: 6)
    ) -> DestinationMetadata {
        DestinationMetadata(
            kind: .token,
            destination: try! PublicKey(base58: "11111111111111111111111111111111"),
            mint: .usdf,
            isValid: true,
            requiresInitialization: requiresInitialization,
            fee: fee
        )
    }
}
