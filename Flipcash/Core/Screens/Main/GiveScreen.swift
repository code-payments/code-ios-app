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
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @State private var enteredAmount: String = ""
    @State private var actionState: ButtonState = .normal
    @State private var isShowingCurrencySelection: Bool = false
    
    @State private var dialogItem: DialogItem?
    
    private let kind: Kind
    
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
    
    init(isPresented: Binding<Bool>, kind: Kind) {
        self._isPresented = isPresented
        self.kind         = kind
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
                        enteredFiat != nil && (enteredFiat?.usdc.quarks ?? 0) > 0
                    },
                    action: nextAction,
                    currencySelectionAction: showCurrencySelection
                )
                .foregroundColor(.textMain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, -20)
                .sheet(isPresented: $isShowingCurrencySelection) {
                    CurrencySelectionScreen(
                        isPresented: $isShowingCurrencySelection,
                        kind: .entry,
                        ratesController: ratesController
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
        }
        .dialog(item: $dialogItem)
    }
    
    // MARK: - Actions -
    
    private func nextAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        guard session.hasSufficientFunds(for: exchangedFiat) else {
            showInsufficientBalanceError()
            return
        }
        
        isPresented = false
        
        Task {
            try await Task.delay(milliseconds: 50)
            
            switch kind {
            case .cash:
                session.showCashBill(
                    .init(
                        kind: .cash,
                        exchangedFiat: exchangedFiat,
                        received: false
                    )
                )
                
            case .cashLink:
//                session.showCashLinkBillWithShareSheet(exchangedFiat: exchangedFiat)
                break
            }
        }
    }
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
    
    // MARK: - Errors -
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "Insufficient Balance",
            subtitle: "Please enter a lower amount and try again",
            dismissable: true
        ) {
            .okay(kind: .destructive)
        }
    }
}

extension GiveScreen {
    enum Kind {
        
        case cash
        case cashLink
        
        fileprivate var navigationTitle: String {
            switch self {
            case .cash:     "Give"
            case .cashLink: "Send"
            }
        }
    }
}
