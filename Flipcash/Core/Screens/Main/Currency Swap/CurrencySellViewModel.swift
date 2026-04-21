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
            balance: balance.map { FiatAmount.usd($0.usdf.decimalValue) },
            tokenBalanceQuarks: balance?.quarks
        )
    }

    var canPerformAction: Bool {
        guard enteredFiat != nil else {
            return false
        }

        return EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: maxPossibleAmount.nativeAmount.asQuarks
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

        // Navigate to the next screen
        path.append(.confirmation)
    }
                    
}

enum CurrencySellPath: Hashable {
    case confirmation
    case processing(swapId: SwapId, currencyName: String, amount: ExchangedFiat)
}
