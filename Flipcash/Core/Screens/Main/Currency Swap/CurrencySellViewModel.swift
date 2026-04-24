//
//  CurrencySellViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor @Observable
class CurrencySellViewModel: Identifiable {
    var enteredAmount: String = ""
    var path: [CurrencySellPath] = []
    @ObservationIgnored let currencyMetadata: StoredMintMetadata
    /// Pinned at construction so every `ExchangedFiat.compute` on this VM uses
    /// the same rate and bonded supply the intent will be validated against.
    /// Mirrors the `CurrencyBuyViewModel` contract.
    @ObservationIgnored let pinnedState: VerifiedState

    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else { return nil }
        // Pinned supply and rate are the single source of truth — using the
        // live cache here lets the stream deliver a fresh supply/rate mid-entry
        // and produce "native amount and quark value mismatch" at submit.
        guard let supplyQuarks = pinnedState.supplyFromBonding else { return nil }
        let rate = pinnedState.rate
        let balance = session.balance(for: currencyMetadata.mint)

        return ExchangedFiat.compute(
            fromEntered: FiatAmount(value: amount, currency: rate.currency),
            rate: rate,
            mint: currencyMetadata.mint,
            supplyQuarks: supplyQuarks,
            balance: balance.map(\.usdf),
            tokenBalanceQuarks: balance?.quarks
        )
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else {
            return false
        }
        // The pin may age past `clientMaxAge` while the user is on the entry
        // screen — gate Next so the user doesn't tap into a sell that will
        // bounce off Session's `assertFresh`.
        guard !pinnedState.isStale else {
            return false
        }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount
        )
    }

    var screenTitle: String {
        return "Amount To Sell"
    }

    var maxPossibleAmount: ExchangedFiat {
        let entryRate = pinnedState.rate
        let zero = ExchangedFiat.compute(
            onChainAmount: .zero(mint: currencyMetadata.mint),
            rate: entryRate,
            supplyQuarks: nil
        )

        guard let balance = session.balance(for: currencyMetadata.mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: entryRate)
    }

    @ObservationIgnored private let session: Session

    // MARK: - Init -

    init(currencyMetadata: StoredMintMetadata, pinnedState: VerifiedState, session: Session) {
        self.currencyMetadata = currencyMetadata
        self.pinnedState = pinnedState
        self.session = session
    }

    // MARK: - Actions -

    func showConfirmationScreen() {
        guard enteredFiat != nil else { return }
        path.append(.confirmation)
    }
}

enum CurrencySellPath: Hashable {
    case confirmation
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}
