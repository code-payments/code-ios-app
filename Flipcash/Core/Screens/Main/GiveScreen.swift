//
//  GiveScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct GiveScreen: View {
    
    @Binding var isPresented: Bool
    
    @ObservedObject private var viewModel: ScanViewModel
    
    @State private var enteredAmount: String = ""
    @State private var actionState: ButtonState = .normal
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    private var isSendEnabled: Bool {
        true
    }
    
    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
            trace(.failure, components: "[Give] Failed to parse amount string: \(enteredAmount)")
            return nil
        }
        
        let currency = ratesController.entryCurrency
        
        guard let rate = ratesController.rate(for: currency) else {
            trace(.failure, components: "[Give] Rate not found for: \(currency)")
            return nil
        }
        
        guard let converted = try? Fiat(fiatDecimal: amount, currencyCode: currency) else {
            trace(.failure, components: "[Give] Invalid amount for entry")
            return nil
        }
        
        return try! ExchangedFiat(converted: converted, rate: rate)
    }
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, scanViewModel: ScanViewModel) {
        self._isPresented = isPresented
        self.viewModel = scanViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .currency,
                    enteredAmount: $enteredAmount,
                    actionState: $actionState,
                    actionEnabled: { _ in
                        enteredFiat != nil
                    },
                    action: showBill
                )
                .foregroundColor(.textMain)
                .padding(20)
            }
            .navigationBarTitle(Text("Give"), displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
    }
    
    // MARK: - Actions -
    
    private func showBill() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        isPresented = false
        
        Task {
            try await Task.delay(milliseconds: 50)
            viewModel.showCashBill(
                .init(
                    kind: .cash,
                    exchangedFiat: exchangedFiat,
                    received: false
                )
            )
        }
    }
}
