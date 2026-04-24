//
//  CurrencySellViewModel.swift
//  Code
//
//  Created by Raul Riera on 2025-12-30.
//

import SwiftUI
import FlipcashCore
import FlipcashUI
import Logging

private let logger = Logger(label: "flipcash.swap-service")

@MainActor @Observable
class CurrencySellViewModel: Identifiable {
    var enteredAmount: String = ""
    var path: [CurrencySellPath] = []
    @ObservationIgnored let currencyMetadata: StoredMintMetadata
    /// Observed so `canPerformAction`'s stale gate re-evaluates when the async
    /// pin fetch resolves. `private(set)` because only `showConfirmationScreen`
    /// writes to it.
    private(set) var pinnedState: VerifiedState?
        
    var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else { return nil }
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else { return nil }
        guard let supplyQuarks = currencyMetadata.supplyFromBonding else { return nil }
        let balance = session.balance(for: currencyMetadata.mint)
        let rate = ratesController.rateForEntryCurrency()

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
        // If the pin is fetched but stale, the confirmation submit will reject —
        // gate Next here too so the user doesn't tap into a dead end.
        if let pinned = pinnedState, pinned.isStale {
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
        let entryRate = ratesController.rateForEntryCurrency()
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
    @ObservationIgnored private let ratesController: RatesController
    
    // MARK: - Init -
    
    init(currencyMetadata: StoredMintMetadata, session: Session, ratesController: RatesController) {
        self.currencyMetadata = currencyMetadata
        self.session          = session
        self.ratesController  = ratesController
    }
        
    // MARK: - Actions -

    func showConfirmationScreen() {
        guard enteredFiat != nil else {
            return
        }

        let mint = currencyMetadata.mint
        let currency = ratesController.entryCurrency

        Task {
            guard let pinned = await ratesController.currentPinnedState(for: currency, mint: mint) else {
                logger.warning("Sell: no verified state available at confirmation entry", metadata: [
                    "mint": "\(mint.base58)",
                    "currency": "\(currency)",
                ])
                return
            }
            pinnedState = pinned
            path.append(.confirmation)
        }
    }
                    
}

enum CurrencySellPath: Hashable {
    case confirmation
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}
