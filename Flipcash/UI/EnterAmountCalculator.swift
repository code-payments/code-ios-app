//
//  EnterAmountCalculator.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-01-03.
//

import Foundation
import FlipcashCore

struct EnterAmountCalculator {    
    /// Provides exchange rate lookup capability
    typealias RateProvider = (CurrencyCode) -> Rate?
    /// Provides transaction limits for a given currency
    typealias TransactionLimitProvider = (CurrencyCode) -> Quarks?
    
    // MARK: - Properties
    
    let mode: EnterAmountView.Mode
    let entryCurrency: CurrencyCode
    let onrampCurrency: CurrencyCode
    let transactionLimitProvider: TransactionLimitProvider
    let rateProvider: RateProvider
    
    // MARK: - Computed
    
    var currency: CurrencyCode {
        switch mode {
        case .currency, .buy:
            entryCurrency
        case .onramp:
            onrampCurrency
        case .walletDeposit, .phantomDeposit, .withdraw:
            .usd
        }
    }
    
    var maxTransactionAmount: Quarks {
        transactionLimitProvider(currency) ?? 0
    }
    
    // MARK: - Methods
    
    func maxEnterAmount(maxBalance: ExchangedFiat) -> Quarks {
        guard let rate = rateProvider(maxBalance.converted.currencyCode) else {
            return maxBalance.converted
        }
        
        // Convert the transaction limit from USD to the entry currency before comparing
        // Always use USDF decimals (6) since maxTransactionAmount comes from limits which are stored in USDC decimals
        let transactionLimitInEntryCurrency = maxTransactionAmount.converting(
            to: rate,
            decimals: PublicKey.usdf.mintDecimals
        )
        
        return min(maxBalance.converted, transactionLimitInEntryCurrency)
    }
}
