//
//  EnterPoolAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct EnterPoolAmountScreen: View {
    
    @EnvironmentObject private var ratesController: RatesController
    
    @ObservedObject private var viewModel: PoolViewModel
    
    @State private var isShowingCurrencySelection: Bool = false
    
    // MARK: - Init -
    
    init(viewModel: PoolViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredPoolAmount,
                subtitle: .singleTransactionLimit,
                actionState: .constant(.normal),
                actionEnabled: { _ in
                    viewModel.enteredPoolFiat != nil && (viewModel.enteredPoolFiat?.usdc.quarks ?? 0) > 0
                },
                action: viewModel.submitPoolAmountAction,
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
        .navigationTitle("Cost to Join")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
    }
    
    // MARK: - Actions -
    
    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
