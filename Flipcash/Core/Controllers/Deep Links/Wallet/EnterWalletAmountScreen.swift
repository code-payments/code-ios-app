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
    
    @EnvironmentObject private var ratesController: RatesController
    
    @State private var actionState: ButtonState = .normal
    @State private var enteredAmount: String = ""
    
//    @State private var isShowingCurrencySelection: Bool = false
    
    private var fiat: Fiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            return nil
        }
        
        return try! Fiat(
            fiatDecimal: amount,
            currencyCode: .usd,
            decimals: PublicKey.usdc.mintDecimals
        )
    }
    
    private let amountEntered: (Fiat) async throws -> Void
    
    // MARK: - Init -
    
    init(amountEntered: @escaping (Fiat) async throws -> Void) {
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
                actionEnabled: { _ in
                    fiat != nil && (fiat?.quarks ?? 0) > 0
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
        .navigationTitle("Amount to Deposit")
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
