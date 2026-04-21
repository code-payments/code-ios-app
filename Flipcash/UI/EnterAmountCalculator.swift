//
//  EnterAmountCalculator.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-01-03.
//

import Foundation
import FlipcashCore

struct EnterAmountCalculator {
    /// Provides the full SendLimit for a given currency
    typealias SendLimitProvider = (CurrencyCode) -> SendLimit?

    // MARK: - Properties

    let mode: EnterAmountView.Mode
    let entryCurrency: CurrencyCode
    let sendLimitProvider: SendLimitProvider

    // MARK: - Computed

    var currency: CurrencyCode {
        switch mode {
        case .currency, .buy, .sell:
            entryCurrency
        case .onramp, .walletDeposit, .phantomDeposit:
            .usd
        case .withdraw:
            entryCurrency
        }
    }

    /// The maximum amount the user can enter for a single transaction, determined by flow type.
    /// Returns `nil` for flows that have no per-transaction cap (sell, withdraw). Used by
    /// `EnterAmountView` for the "Enter up to X" subtitle and button-enable logic.
    var maxTransactionAmount: Quarks? {
        switch mode {
        case .currency:
            // Give: effective limit is the lower of per-tx cap and remaining daily
            guard let limit = sendLimitProvider(currency) else { return nil }
            return min(limit.maxPerTransaction, limit.nextTransaction)
        case .buy, .phantomDeposit, .walletDeposit, .onramp:
            // Buy-style flows: per-tx limit is the daily cap (no daily accumulation limit)
            guard let limit = sendLimitProvider(currency) else { return nil }
            return limit.maxPerDay
        case .sell, .withdraw:
            // No per-transaction limits for these flows
            return nil
        }
    }
    
    // MARK: - Static

    static func isWithinDisplayLimit(enteredAmount: String, max: Quarks) -> Bool {
        guard let amount = NumberFormatter.decimal(from: enteredAmount), amount > 0 else {
            return false
        }
        // Use a currency-aware formatter to parse back the display value.
        // The generic parsers in NumberFormatter.decimal(from:) can't parse
        // currency symbols that don't match the device locale (e.g. ¥ on en_US).
        let formatter = NumberFormatter.fiat(
            currency: max.currencyCode,
            minimumFractionDigits: max.currencyCode.maximumFractionDigits
        )
        let displayMax = formatter.number(from: max.formatted())?.decimalValue ?? 0
        return amount <= displayMax
    }

    // MARK: - Methods

    func maxEnterAmount(maxBalance: ExchangedFiat) -> Quarks {
        let balanceAsQuarks = maxBalance.nativeAmount.asQuarks

        // Unbounded flows (sell, withdraw, deposit): cap at balance only.
        guard let limit = maxTransactionAmount else {
            return balanceAsQuarks
        }

        // Server-provided limits are already localized to the entry currency,
        // and the balance is also in the entry currency, so we can compare
        // directly. No fx conversion needed.
        guard limit.currencyCode == balanceAsQuarks.currencyCode else {
            return balanceAsQuarks
        }

        return min(balanceAsQuarks, limit)
    }
}
