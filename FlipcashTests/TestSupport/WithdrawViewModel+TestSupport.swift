//
//  WithdrawViewModel+TestSupport.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-02-27.
//

import Foundation
import SwiftUI
import Testing
import FlipcashCore
import FlipcashUI
@testable import FlipcashCore
@testable import Flipcash

@MainActor
enum WithdrawViewModelTestHelpers {

    static func createViewModel(
        balanceCurrency: CurrencyCode = .usd,
        rates: [Rate] = [.oneToOne],
        withdrawalFeeQuarks: UInt64 = 50_000
    ) -> WithdrawViewModel {
        let container = Container.mock
        let sessionContainer = SessionContainer.mock

        sessionContainer.ratesController.configureTestRates(
            balanceCurrency: balanceCurrency,
            rates: rates
        )

        sessionContainer.session.userFlags = UserFlags(
            isRegistered: true,
            isStaff: false,
            onrampProviders: [],
            preferredOnrampProvider: .unknown,
            minBuildNumber: 0,
            billExchangeDataTimeout: nil,
            newCurrencyPurchaseAmount: .zero(mint: .usdf),
            newCurrencyFeeAmount: .zero(mint: .usdf),
            withdrawalFeeAmount: TokenAmount(quarks: withdrawalFeeQuarks, mint: .usdf)
        )

        return WithdrawViewModel(
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
            exchangedFiat: ExchangedFiat.compute(
                onChainAmount: TokenAmount(quarks: quarks, mint: mint),
                rate: .oneToOne,
                supplyQuarks: nil
            )
        )
    }

    /// A bonded-mint `ExchangedBalance` backed by a live-supply entry. Use
    /// when a test needs `supplyFromBonding` to be set so the bonding-curve
    /// paths in the view model (`exchangedFee`, `enteredFiat`) run.
    static func createBondedBalance(
        mint: PublicKey = .jeffy,
        quarks: UInt64 = 100 * 10_000_000_000, // 100 whole tokens (10 decimals)
        supplyFromBonding: UInt64 = 50_000 * 10_000_000_000
    ) -> ExchangedBalance {
        let stored = try! StoredBalance(
            quarks: quarks,
            symbol: "TEST",
            name: "Test Token",
            supplyFromBonding: supplyFromBonding,
            sellFeeBps: 0,
            mint: mint,
            vmAuthority: .usdcAuthority,
            updatedAt: Date(),
            imageURL: nil,
            costBasis: 0
        )

        return ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: .oneToOne)
        )
    }

    /// Builds a `SessionContainer` seeded with a USDF holding and returns a
    /// matching `ExchangedBalance` ready to drop into `viewModel.kind`. Use
    /// when a test needs `session.balance(for:)` populated so
    /// `hasSufficientFunds` returns `.sufficient` and the kind gate (not the
    /// funds gate) is the deciding factor.
    ///
    /// Pass `withdrawalFeeQuarks` > 0 when the test depends on
    /// `userFlags.withdrawalFeeAmount` (e.g. fee-gating via
    /// `isBelowMinimumWithdraw`).
    static func makeUSDFFixture(
        quarks: UInt64 = 10_000_000,
        withdrawalFeeQuarks: UInt64 = 0
    ) throws -> (container: SessionContainer, balance: ExchangedBalance) {
        let container = try SessionContainer.makeTest(holdings: [
            .init(mint: MintMetadata.usdf, quarks: quarks)
        ])
        if withdrawalFeeQuarks > 0 {
            container.session.userFlags = UserFlags(
                isRegistered: true,
                isStaff: false,
                onrampProviders: [],
                preferredOnrampProvider: .unknown,
                minBuildNumber: 0,
                billExchangeDataTimeout: nil,
                newCurrencyPurchaseAmount: .zero(mint: .usdf),
                newCurrencyFeeAmount: .zero(mint: .usdf),
                withdrawalFeeAmount: TokenAmount(quarks: withdrawalFeeQuarks, mint: .usdf)
            )
        }
        let stored = try #require(container.session.balance(for: .usdf))
        let rate = container.ratesController.rateForBalanceCurrency()
        let balance = ExchangedBalance(
            stored: stored,
            exchangedFiat: stored.computeExchangedValue(with: rate)
        )
        return (container, balance)
    }

    static func createDestinationMetadata(
        kind: DestinationMetadata.Kind = .owner,
        isValid: Bool = true,
        requiresInitialization: Bool = false,
        fee: TokenAmount = TokenAmount(quarks: 0, mint: .usdf)
    ) -> DestinationMetadata {
        DestinationMetadata(
            kind: kind,
            destination: try! PublicKey(base58: "11111111111111111111111111111111"),
            mint: .usdf,
            isValid: isValid,
            requiresInitialization: requiresInitialization,
            fee: fee
        )
    }
}
