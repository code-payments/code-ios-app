//
//  MinimumBalanceAmountSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The custom minimum balance behind the form's `…` preset (node 10127:118014).
///
/// Pinned to USD rather than the wallet's display currency: the gate weighs `StoredBalance.usdf`,
/// the holding's USD worth resolved at store time, so a requirement entered in USD needs no rate to
/// enforce and cannot drift with one.
struct MinimumBalanceAmountSheet: View {

    /// The amount the form already holds, so reopening the sheet starts on it rather than empty.
    let initialAmount: FiatAmount?

    @Binding var isPresented: Bool

    let onSelect: (FiatAmount) -> Void

    @State private var enteredAmount: String = ""

    /// Whole dollars only past nine digits is what every other amount field allows; the two decimal
    /// places match the currency the requirement is denominated in.
    private static let rules = KeyPadView.CurrencyRules(maxIntegerDigits: 9, maxDecimalDigits: 2)

    private let validator = AmountValidator()

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(spacing: 0) {
                    Spacer()

                    AmountField(
                        content: $enteredAmount,
                        defaultValue: .number("0"),
                        prefix: .none,
                        formatter: .fiat(currency: .usd, minimumFractionDigits: 0),
                        suffix: nil,
                        showChevron: false
                    )
                    .foregroundStyle(enteredAmount.isEmpty ? Color.textTertiary : Color.textMain)

                    Spacer()

                    KeyPadView(
                        content: $enteredAmount,
                        configuration: .decimal(),
                        rules: Self.rules
                    )
                    .padding(.bottom, 12)

                    CodeButton(style: .filled, title: "Done", disabled: amount == nil) {
                        guard let amount else { return }
                        onSelect(amount)
                        isPresented = false
                    }
                    .accessibilityIdentifier("minimum-balance-done-button")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("Minimum Balance")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear {
            guard let initialAmount else { return }
            enteredAmount = validator.string(from: initialAmount.value, fractionDigits: 2)
        }
    }

    /// The entered amount, or nil while the field holds nothing the requirement can be set to.
    /// Parsed only through ``AmountValidator``, never from the raw keypad string.
    private var amount: FiatAmount? {
        guard let value = validator.validate(enteredAmount), value > 0 else { return nil }
        return .usd(value)
    }
}
