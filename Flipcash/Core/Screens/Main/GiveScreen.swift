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
    
    @ObservedObject private var onrampViewModel: OnrampViewModel
    
    @State private var enteredAmount: String = ""
    @State private var actionState: ButtonState = .normal
    
    @State private var isShowingCurrencySelection: Bool = false
    @State private var isShowingDepositScreen: Bool = false
    
    @State private var dialogItem: DialogItem?
    
    private var enteredFiat: ExchangedFiat? {
        guard !enteredAmount.isEmpty else {
            return nil
        }
        
        guard let amount = NumberFormatter.decimal(from: enteredAmount) else {
//            trace(.failure, components: "[Give] Failed to parse amount string: \(enteredAmount)")
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
        
        return try! ExchangedFiat(
            converted: converted,
            rate: rate,
            mint: .usdc
        )
    }
    
    private let kind: Kind
    private let container: Container
    private let sessionContainer: SessionContainer
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, kind: Kind, container: Container, sessionContainer: SessionContainer) {
        self._isPresented     = isPresented
        self.kind             = kind
        self.container        = container
        self.sessionContainer = sessionContainer
        self.onrampViewModel  = sessionContainer.onrampViewModel
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
            .navigationDestination(isPresented: $isShowingDepositScreen) {
                DepositDescriptionScreen(session: session)
            }
            .sheet(isPresented: $onrampViewModel.isMethodSelectionPresented) {
                AddCashScreen(
                    isPresented: $onrampViewModel.isMethodSelectionPresented,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .sheet(isPresented: $onrampViewModel.isOnrampPresented) {
                PartialSheet(background: .backgroundMain) {
                    PresetAddCashScreen(
                        isPresented: $onrampViewModel.isOnrampPresented,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
            }
        }
        .dialog(item: $dialogItem)
        .dialog(item: $onrampViewModel.purchaseSuccess)
    }
    
    // MARK: - Actions -
    
    private func nextAction() {
        guard let exchangedFiat = enteredFiat else {
            return
        }
        
        let (hasSufficientFunds, delta) = session.hasSufficientFundsWithDelta(for: exchangedFiat)
        
        guard hasSufficientFunds else {
            if let delta {
                showYoureShortError(amount: delta)
            } else {
                showInsufficientBalanceError()
            }
            return
        }
        
        guard session.hasLimitToSendFunds(for: exchangedFiat) else {
            showLimitsError()
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
    
    private func presentOnramp() {
        onrampViewModel.presentRoot()
        Analytics.onrampOpenedFromGive()
    }
    
    // MARK: - Errors -
    
    private func showInsufficientBalanceError() {
        dialogItem = .init(
            style: .destructive,
            title: "You Need More Cash",
            subtitle: "Please add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") {
                presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showYoureShortError(amount: ExchangedFiat) {
        dialogItem = .init(
            style: .destructive,
            title: "You're \(amount.converted.formatted(suffix: nil)) Short",
            subtitle: "Add more cash, or try again with a lower amount",
            dismissable: true
        ) {
            .destructive("Add More Cash") {
                presentOnramp()
            };
            .dismiss(kind: .subtle)
        }
    }
    
    private func showLimitsError() {
        dialogItem = .init(
            style: .destructive,
            title: "Transaction Limit Reached",
            subtitle: "Flipcash is designed for small, every day transactions. Send limits reset daily",
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
