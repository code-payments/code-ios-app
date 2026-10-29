//
//  TrayAmountEntry.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// The amount picker at tray size: the full-screen entry's amount, hint and keypad, left-aligned,
/// with the amount scaled down and the keypad running the tray's full width.
///
/// The caller owns `amount`, the keypad's raw string, and parses it for its CTA; this view only
/// edits and draws it, with the full-screen entry's components and digit limits.
public struct TrayAmountEntry: View {

    @Binding private var amount: String

    private let currency: CurrencyCode
    private let caption: String?
    private let isCaptionError: Bool

    /// Creates an entry that edits `amount` within `currency`'s digit limits; `isCaptionError` draws the caption as an error.
    public init(amount: Binding<String>, currency: CurrencyCode, caption: String? = nil, isCaptionError: Bool = false) {
        self._amount = amount
        self.currency = currency
        self.caption = caption
        self.isCaptionError = isCaptionError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The full-screen header's amount and hint (`EnterAmountHeader`), at the tray's size.
            VStack(alignment: .leading, spacing: TrayAmountMetrics.amountToCaption) {
                AmountField(
                    content: $amount,
                    defaultValue: .number("0"),
                    prefix: .none,
                    formatter: .fiat(currency: currency, minimumFractionDigits: 0),
                    suffix: nil,
                    font: .default(size: TrayAmountMetrics.amountSize, weight: .bold),
                    height: TrayAmountMetrics.amountHeight
                )
                .foregroundStyle(amount.isEmpty ? Color.textTertiary : Color.textMain)

                if let caption {
                    Text(caption)
                        .font(.default(size: TrayAmountMetrics.captionSize))
                        .foregroundStyle(isCaptionError ? Color.textError : Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KeyPadView(
                content: $amount,
                configuration: currency.maximumFractionDigits > 0 ? .decimal() : .number(),
                rules: KeyPadView.CurrencyRules(maxIntegerDigits: 9, maxDecimalDigits: currency.maximumFractionDigits)
            )
            // The screen-coloured key tint would show on the lighter tray.
            .environment(\.keyPadRestFill, .clear)
            .padding(.horizontal, -TrayAmountMetrics.keypadSideBleed)
            .padding(.top, TrayAmountMetrics.captionToKeypad)
        }
    }
}

#Preview("Amount entry") {
    @Previewable @State var amount = ""
    TrayPage {
        TrayAmountEntry(amount: $amount, currency: .usd, caption: "$1,250.00 available")
    }
    .padding(24)
    .background(Color.backgroundMain)
}
