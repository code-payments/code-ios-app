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
    
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var ratesController: RatesController
    
    @StateObject private var viewModel: WithdrawViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    // MARK: - Init -
    
    init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented = isPresented
        _viewModel = .init(
            wrappedValue: WithdrawViewModel(
                isPresented: isPresented,
                container: container,
                sessionContainer: sessionContainer
            )
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $viewModel.path) {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .currency,
                    enteredAmount: $viewModel.enteredAmount,
                    actionState: .constant(.normal),
                    actionEnabled: { _ in
                        viewModel.enteredFiat != nil
                    },
                    action: viewModel.amountEnteredAction,
                    currencySelectionAction: showCurrencySelection
                )
                .foregroundColor(.textMain)
                .padding(20)
                .sheet(isPresented: $isShowingCurrencySelection) {
                    CurrencySelectionScreen(
                        isPresented: $isShowingCurrencySelection,
                        kind: .entry,
                        ratesController: ratesController
                    )
                }
            }
            .navigationTitle("Withdraw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(for: WithdrawNavigationPath.self) { path in
                switch path {
                case .enterAddress:
                    WithdrawAddressScreen(viewModel: viewModel)
                case .confirmation:
                    WithdrawSummaryScreen(viewModel: viewModel)
                }
            }
        }
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Actions -
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
