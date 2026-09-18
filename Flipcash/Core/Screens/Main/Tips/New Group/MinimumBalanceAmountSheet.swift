//
//  MinimumBalanceAmountSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The custom balance requirement behind the form's `…` preset (node 10127:118014).
///
/// Built on ``EnterAmountView``, the same screen the tip and Minimum To Chat flows enter amounts
/// on, so the entry is in the account's display currency and the keypad behaves the way it does
/// everywhere else.
///
/// The requirement itself is still USD. The gate weighs `StoredBalance.usdf` — the holding's USD
/// worth resolved at store time — so a requirement stored in USD needs no rate to enforce and
/// cannot drift with one. The single conversion is the one applied here, at the moment the amount
/// is set, which is where Android puts it too.
struct MinimumBalanceAmountSheet: View {

    /// The requirement the form already holds, in USD, so reopening the sheet starts on it rather
    /// than empty.
    let initialAmount: FiatAmount?

    @Binding var isPresented: Bool

    let onSelect: (FiatAmount) -> Void

    @Environment(RatesController.self) private var ratesController

    @State private var enteredAmount: String = ""
    @State private var actionState: ButtonState = .normal

    private let validator = AmountValidator()

    private var currency: CurrencyCode { ratesController.balanceCurrency }

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .balanceRequirement,
                    enteredAmount: $enteredAmount,
                    subtitle: .hidden,
                    actionState: $actionState,
                    actionEnabled: { _ in amount != nil },
                    action: submit,
                    header: AnyView(EnterAmountHeader(
                        enteredAmount: $enteredAmount,
                        // The same sentence the form prints under the preset row: the sheet is
                        // setting the figure that sentence is about, and it is the only thing on
                        // screen saying what the amount does.
                        hint: .description(
                            "People won't be able to join this chat if their balance is less than this amount"
                        )
                    ))
                )
                .foregroundStyle(.textMain)
                .padding(20)
            }
            .ignoresSafeArea(.keyboard)
            .navigationTitle("Balance Requirement")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(binding: $isPresented)
                }
            }
        }
        .onAppear(perform: seed)
    }

    /// The entry restated in USD, or nil while the field holds nothing the requirement can be set
    /// to. Parsed only through ``AmountValidator``, never from the raw keypad string.
    ///
    /// Nil as well when the rate the conversion needs hasn't landed, and when the entry is small
    /// enough to round away to nothing in USD — both would otherwise set a requirement no one has
    /// to clear. Done is disabled in every one of those states, so a zero can't be submitted.
    private var amount: FiatAmount? {
        guard let value = validator.validate(enteredAmount), value > 0,
              let usd = FiatAmount(value: value, currency: currency)
                  .converted(to: .usd, rates: ratesController.cachedRates),
              usd.isPositive else { return nil }
        return usd
    }

    private func submit() {
        guard let amount else { return }
        onSelect(amount)
        isPresented = false
    }

    /// Starts the field on the requirement already set, restated in the currency being entered.
    ///
    /// Seeded on appear rather than in `init`, which has no rates to convert with. A requirement
    /// whose currency has no rate seeds nothing rather than a figure in the wrong denomination.
    private func seed() {
        guard let initialAmount,
              let native = initialAmount.converted(to: currency, rates: ratesController.cachedRates),
              native.isPositive else { return }
        enteredAmount = validator.string(
            from: native.value,
            fractionDigits: currency.maximumFractionDigits
        )
    }
}
