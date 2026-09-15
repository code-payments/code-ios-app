//
//  EnterAmountHeader.swift
//  Flipcash
//
//  The top half of the left-aligned amount screens — Convert / Get / Give and
//  Minimum To Chat: a large amount field over a hint. Dropped into
//  `EnterAmountView` via its `header` slot, replacing the default centered
//  amount + "Enter up to" subtitle.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterAmountHeader: View {

    /// The line under the amount.
    enum Hint {
        /// "$X available", reddening once the entry exceeds it — the spend
        /// flows, where the balance is the ceiling.
        case available(ExchangedFiat)
        /// Fixed one-line secondary copy, e.g. "$1.00 minimum". Never reddens:
        /// flows that use it state their bound up front and report a breach
        /// through a dialog on submit rather than by colouring the hint.
        case caption(String)
        /// A sentence saying what the amount is for, wrapping over as many lines
        /// as it needs. Set a step smaller than the other two, which carry a
        /// value rather than prose.
        case description(String)
    }

    @Binding var enteredAmount: String
    let hint: Hint

    @Environment(RatesController.self) private var ratesController

    private var currency: CurrencyCode { ratesController.balanceCurrency }

    /// Mirrors `EnterAmountView`'s overrun colouring: the hint turns red once the
    /// entry exceeds what's available.
    private var isExceeding: Bool {
        guard case .available(let available) = hint else { return false }
        guard let value = AmountValidator().validate(enteredAmount), value > 0 else { return false }
        return !EnterAmountCalculator.isWithinDisplayLimit(
            enteredAmount: enteredAmount,
            max: available.nativeAmount
        )
    }

    private var hintText: String {
        switch hint {
        case .available(let available): "\(available.nativeAmount.formatted()) available"
        case .caption(let text):        text
        case .description(let text):    text
        }
    }

    private var hintFont: Font {
        switch hint {
        case .available, .caption: .appTextMedium
        case .description:         .appTextSmall
        }
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

            Text(hintText)
                .font(hintFont)
                .foregroundStyle(isExceeding ? Color.textError : Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
