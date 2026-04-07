//
//  OnrampAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct OnrampAmountScreen: View {

    @Bindable private var viewModel: OnrampViewModel

    // MARK: - Init -

    init(viewModel: OnrampViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $viewModel.onrampPath) {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .onramp,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: $viewModel.payButtonState,
                    actionEnabled: { _ in
                        viewModel.enteredFiat != nil
                    },
                    action: viewModel.customAmountEnteredAction,
                    currencySelectionAction: nil,
                )
                .foregroundColor(.textMain)
                .padding(20)
                .overlay {
                    viewModel.applePayWebView()
                }
            }
            .navigationTitle("Amount to Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.isProcessingPayment {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton(binding: $viewModel.isOnrampPresented)
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isProcessingPayment)
            .navigationDestination(for: OnrampPath.self) { path in
                switch path {
                case .swapProcessing(let swapId, let currencyName, let amount):
                    SwapProcessingScreen(
                        swapId: swapId,
                        swapType: .buyWithCoinbase,
                        currencyName: currencyName,
                        amount: amount
                    )
                case .info, .enterPhoneNumber, .confirmPhoneNumberCode, .enterEmail, .confirmEmailCode:
                    // Verification destinations are pushed inside VerifyInfoScreen's own
                    // NavigationStack (which also binds onrampPath). They're never reached
                    // here because OnrampAmountScreen's stack is only active after the
                    // verification sheet has dismissed.
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingVerificationFlow) {
            VerifyInfoScreen(viewModel: viewModel)
        }
        .dialog(item: $viewModel.dialogItem)
    }
}
