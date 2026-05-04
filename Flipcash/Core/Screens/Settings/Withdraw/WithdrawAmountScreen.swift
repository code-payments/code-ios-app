//
//  WithdrawAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct WithdrawAmountScreen: View {

    @Environment(RatesController.self) private var ratesController

    let title: String
    @Binding var enteredAmount: String
    let subtitle: EnterAmountView.Subtitle
    let canProceed: Bool
    let onProceed: () -> Void
    let showsCurrencySelection: Bool

    @State private var isShowingCurrencySelection: Bool = false

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .withdraw,
                enteredAmount: $enteredAmount,
                subtitle: subtitle,
                actionState: .constant(.normal),
                actionEnabled: { _ in canProceed },
                action: onProceed,
                currencySelectionAction: showsCurrencySelection ? showCurrencySelection : nil
            )
            .foregroundStyle(Color.textMain)
            .padding(20)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions -

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
