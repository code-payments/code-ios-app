//
//  SwapAmountHeader.swift
//  Flipcash
//
//  The top half of the Convert / Get amount screen: a left-aligned
//  amount field over an "$X available" hint. Shared by both flows (Convert
//  swaps it in for its source amount, Get for the payment amount) and dropped
//  into `EnterAmountView` via its `header` slot, replacing the default centered
//  amount + "Enter up to" subtitle.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SwapAmountHeader: View {
    @Binding var enteredAmount: String
    /// The spendable balance shown as "$X available" and used to flag overrun.
    let available: ExchangedFiat

    @Environment(RatesController.self) private var ratesController

    private var currency: CurrencyCode { ratesController.balanceCurrency }

    /// Mirrors `EnterAmountView`'s overrun colouring: the hint turns red once the
    /// entry exceeds what's available.
    private var isExceeding: Bool {
        guard let value = AmountValidator().validate(enteredAmount), value > 0 else { return false }
        return !EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: available.nativeAmount
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // No flag — the fiat formatter already prefixes the currency symbol
            // ("$5"), so a flag would be redundant here. The placeholder "$0"
            // reads secondary; a real entry is primary. The amount uses the
            // extra-large display token (74pt) per the Convert/Get spec.
            AmountField(
                content: $enteredAmount,
                defaultValue: .number("0"),
                prefix: .none,
                formatter: .fiat(currency: currency, minimumFractionDigits: 0),
                suffix: nil,
                showChevron: false,
                font: .appDisplayExtraLarge,
                height: 90
            )
            .foregroundStyle(enteredAmount.isEmpty ? Color.textTertiary : Color.textMain)

            Text("\(available.nativeAmount.formatted()) available")
                .font(.appTextMedium)
                .foregroundStyle(isExceeding ? Color.textError : Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
