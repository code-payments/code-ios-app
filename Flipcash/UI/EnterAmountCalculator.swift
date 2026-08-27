//
//  EnterAmountCalculator.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-01-03.
//

import Foundation
import FlipcashCore
import FlipcashUI

nonisolated struct EnterAmountCalculator {
    /// Provides the full SendLimit for a given currency
    typealias SendLimitProvider = (CurrencyCode) -> SendLimit?

    // MARK: - Properties

    let mode: EnterAmountView.Mode
    let selectedCurrency: CurrencyCode
    let sendLimitProvider: SendLimitProvider

    // MARK: - Computed

    var currency: CurrencyCode {
        switch mode {
        case .currency, .buy, .sell, .convert, .withdraw, .addMoney:
            selectedCurrency
        }
    }

    /// The maximum amount the user can enter for a single transaction, determined by flow type.
    /// Returns `nil` for flows that have no per-transaction cap (sell, withdraw). Used by
    /// `EnterAmountView` for the "Enter up to X" subtitle and button-enable logic.
    var maxTransactionAmount: FiatAmount? {
        switch mode {
        case .currency:
            // Give: effective limit is the lower of per-tx cap and remaining daily
            guard let limit = sendLimitProvider(currency) else { return nil }
            return min(limit.maxPerTransaction, limit.nextTransaction)
        case .buy:
            // Buy entry is capped by the highest spendable balance, not the
            // send limit — the limit check happens at submission on the Buy
            // summary.
            return nil
        case .addMoney:
            // Add Money: per-tx limit is the daily cap (no daily accumulation limit)
            guard let limit = sendLimitProvider(currency) else { return nil }
            return limit.maxPerDay
        case .sell, .convert, .withdraw:
            // No per-transaction limits for these flows — capped by balance.
            return nil
        }
    }

    // MARK: - Static

    static func isWithinDisplayLimit(enteredAmount: String, max: FiatAmount) -> Bool {
        guard let amount = AmountValidator().validate(enteredAmount), amount > 0 else {
            return false
        }
        // Round to the currency's display precision the same way the formatter
        // does, in Decimal. Formatting the max and parsing the string back went
        // through a double — "$8.54" returned 8.539999999999999, rejecting an
        // entry of exactly the displayed balance.
        let displayMax = max.value.rounded(to: max.currency.maximumFractionDigits)
        return amount <= displayMax
    }

    // MARK: - Methods

    func maxEnterAmount(maxBalance: ExchangedFiat) -> FiatAmount {
        let balance = maxBalance.nativeAmount

        // Unbounded flows (sell, withdraw, deposit): cap at balance only.
        guard let limit = maxTransactionAmount else {
            return balance
        }

        // Server-provided limits are already localized to the user's selected
        // currency, and the balance is too, so we can compare directly. No fx
        // conversion needed.
        guard limit.currency == balance.currency else {
            return balance
        }

        return min(balance, limit)
    }
}
