//
//  EnterWalletAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterWalletAmountScreen: View {

    @Environment(Session.self) private var session

    @State private var actionState: ButtonState = .normal
    @State private var enteredAmount: String = ""

    private var fiat: FiatAmount? {
        guard !enteredAmount.isEmpty else {
            return nil
        }

        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }

        return FiatAmount(value: amount, currency: .usd)
    }

    private let amountEntered: (TokenAmount) async throws -> Void

    // MARK: - Init -

    init(amountEntered: @escaping (TokenAmount) async throws -> Void) {
        self.amountEntered = amountEntered
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .phantomDeposit,
                enteredAmount: $enteredAmount,
                subtitle: .singleTransactionLimit,
                actionState: $actionState,
                actionEnabled: { enteredAmount in
                    guard let fiat, fiat.isPositive else { return false }
                    guard let maxPerDay = session.sendLimitFor(currency: .usd)?.maxPerDay else { return false }
                    return EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: enteredAmount, max: maxPerDay)
                },
                action: nextAction,
                currencySelectionAction: nil
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .navigationTitle("Amount to Buy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions -

    private func nextAction() {
        guard let fiat = fiat else {
            return
        }

        Task {
            actionState = .loading
            defer {
                actionState = .normal
            }

            let usdc = TokenAmount(wholeTokens: fiat.value, mint: .usdf)
            try await amountEntered(usdc)
        }
    }
}
