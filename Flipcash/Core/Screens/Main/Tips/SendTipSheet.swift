//
//  SendTipSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Send a Tip bottom sheet: three preset chips plus a custom-amount slot,
/// the tip currency, and the swipe-to-send control. Presented over the scanned
/// tipcard with the camera visible behind it.
struct SendTipSheet: View {

    let tipFlow: TipFlow

    @Environment(RatesController.self) private var ratesController

    private enum LocalSheet: String, Identifiable {
        case customAmount
        case currencyPicker

        var id: String { rawValue }
    }

    @State private var localSheet: LocalSheet?

    private var displayCurrency: CurrencyCode {
        ratesController.balanceCurrency
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Send a Tip")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            HStack(spacing: 8) {
                presetChip(.low)
                presetChip(.medium)
                presetChip(.high)
                customChip
            }

            currencyRow

            SwipeControl(text: "Swipe to Tip") {
                try await tipFlow.swipeToTip()
            }
            .disabled(tipFlow.selectedAmount == nil)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .sheet(item: $localSheet) { sheet in
            switch sheet {
            case .customAmount:
                TipCustomAmountSheet(tipFlow: tipFlow)
            case .currencyPicker:
                SelectCurrencyScreen(
                    isPresented: Binding(
                        get: { localSheet == .currencyPicker },
                        set: { if !$0 { localSheet = nil } }
                    )
                ) { balance in
                    tipFlow.selectCurrency(balance)
                }
            }
        }
    }

    // MARK: - Chips -

    private func presetChip(_ tier: TipSelection) -> some View {
        let amount = tipFlow.amount(for: tier)
        return TipAmountChip(
            title: amount.map { FiatAmount(value: $0, currency: displayCurrency).formatted(minimumFractionDigits: 0) } ?? "–",
            isSelected: tipFlow.selection == tier
        ) {
            tipFlow.selection = tier
        }
        .disabled(amount == nil)
        .accessibilityIdentifier("tip-chip-\(tier.rawValue)")
    }

    /// The fourth slot: "…" until a custom amount is set, then that amount.
    /// Tapping always opens the amount entry, so a set amount can be changed.
    private var customChip: some View {
        TipAmountChip(
            title: tipFlow.amount(for: .custom).map { FiatAmount(value: $0, currency: displayCurrency).formatted() } ?? "…",
            isSelected: tipFlow.selection == .custom
        ) {
            localSheet = .customAmount
        }
        .accessibilityIdentifier("tip-custom-chip")
    }

    // MARK: - Currency -

    private var currencyRow: some View {
        HStack(spacing: 6) {
            Text("of")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)

            TokenSelectorButton(selectedBalance: tipFlow.submission?.selectedBalance) {
                localSheet = .currencyPicker
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(Color(white: 0.22))
            }
            .accessibilityIdentifier("tip-currency-row")
        }
    }
}

// MARK: - TipAmountChip -

private struct TipAmountChip: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appTextXL)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isSelected ? Color.backgroundMain : Color.textMain)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isSelected ? Color.textMain : Color(white: 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TipCustomAmountSheet -

/// The "…" chip's amount entry: the standard keypad in the display currency,
/// with the flag opening the standard currency selection (same as Give).
/// Adoption runs through the flow, which enforces the server's tip minimum.
private struct TipCustomAmountSheet: View {

    let tipFlow: TipFlow

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismiss) private var dismiss

    @State private var enteredAmount: String = ""
    @State private var actionState: ButtonState = .normal
    @State private var isShowingCurrencySelection = false

    private let amountValidator = AmountValidator()

    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .currency,
                    enteredAmount: $enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: $actionState,
                    actionEnabled: { amountValidator.validate($0).map { $0 > 0 } ?? false },
                    action: confirm,
                    currencySelectionAction: { isShowingCurrencySelection.toggle() },
                    actionTitle: "Next"
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .sheet(isPresented: $isShowingCurrencySelection) {
                    CurrencySelectionScreen(ratesController: sessionContainer.ratesController)
                }
            }
            .navigationTitle("Amount to Tip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { dismiss() }
                }
            }
        }
    }

    /// Adopts the entered amount; the flow surfaces the minimum dialog and
    /// keeps the entry up when it's too small.
    private func confirm() {
        guard let amount = amountValidator.validate(enteredAmount), amount > 0 else { return }
        if tipFlow.setCustomAmount(amount) {
            dismiss()
        }
    }
}
