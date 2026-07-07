//
//  AddMoneyAmountScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// "Amount to Add" free entry for a Coinbase or Phantom deposit. Mirrors
/// `BuyAmountScreen`: reads onramp/wallet dependencies from the environment,
/// builds its own view model, and hands the entered amount to the deposit
/// operation on tap.
struct AddMoneyAmountScreen: View {

    @State private var viewModel: AddMoneyAmountViewModel

    @Environment(CoinbaseService.self) private var coinbaseService
    @Environment(VerificationCoordinator.self) private var verificationCoordinator
    @Environment(WalletConnection.self) private var walletConnection

    /// Called once the deposit operation is under way — pushes the blocking
    /// "Adding Money" screen onto the enclosing flow sheet's stack.
    private let onProceed: (AddMoneyProcessingInput) -> Void

    init(
        method: DepositMethod,
        session: Session,
        ratesController: RatesController,
        onProceed: @escaping (AddMoneyProcessingInput) -> Void
    ) {
        _viewModel = State(initialValue: AddMoneyAmountViewModel(
            method: method,
            session: session,
            ratesController: ratesController
        ))
        self.onProceed = onProceed
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .addMoney,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .singleTransactionLimit,
                actionState: $viewModel.actionButtonState,
                actionEnabled: { _ in viewModel.canAdd },
                action: {
                    viewModel.addMoney(
                        coinbaseService: coinbaseService,
                        verificationCoordinator: verificationCoordinator,
                        walletConnection: walletConnection,
                        onProceed: onProceed
                    )
                },
                actionTitle: viewModel.actionTitle
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(viewModel.screenTitle)
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $viewModel.dialogItem)
        .sheet(item: $viewModel.verificationViewModel.cancellingOnDismiss()) { vm in
            VerifyInfoScreen(viewModel: vm)
        }
    }
}
