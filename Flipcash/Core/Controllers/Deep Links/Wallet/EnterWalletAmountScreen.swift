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
    
//    @State private var isShowingCurrencySelection: Bool = false
    
    private var fiat: Quarks? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }
        
        return try! Quarks(
            fiatDecimal: amount,
            currencyCode: .usd,
            decimals: PublicKey.usdf.mintDecimals
        )
    }
    
    private let amountEntered: (Quarks) async throws -> Void
    
    // MARK: - Init -
    
    init(amountEntered: @escaping (Quarks) async throws -> Void) {
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
                    guard let fiat, fiat.quarks > 0 else { return false }
                    guard let maxPerDay = session.sendLimitFor(currency: .usd)?.maxPerDay else { return false }
                    return EnterAmountCalculator.isWithinDisplayLimit(enteredAmount: enteredAmount, max: maxPerDay)
                },
                action: nextAction,
                currencySelectionAction: nil//showCurrencySelection
            )
            .foregroundColor(.textMain)
            .padding(20)
//            .sheet(isPresented: $isShowingCurrencySelection) {
//                CurrencySelectionScreen(
//                    isPresented: $isShowingCurrencySelection,
//                    kind: .entry,
//                    ratesController: ratesController
//                )
//            }
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
            
            try await amountEntered(fiat)
        }
    }
    
//    private func showCurrencySelection() {
//        isShowingCurrencySelection.toggle()
//    }
}
