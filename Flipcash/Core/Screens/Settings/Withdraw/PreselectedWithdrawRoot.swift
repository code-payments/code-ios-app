//
//  PreselectedWithdrawRoot.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Withdraw flow entry point that lands the user on `WithdrawIntroScreen`
/// with `mint` already selected on the view model. Used by both the Settings
/// "Withdraw" button (USDF default, with a "Withdraw Other Flipcash
/// Currencies" escape hatch) and the Wallet → USDF Currency Info entry
/// (USDF only, no escape hatch).
struct PreselectedWithdrawRoot: View {

    @Environment(AppRouter.self) private var router
    @State private var viewModel: WithdrawViewModel

    private let popStack: AppRouter.Stack
    private let onWithdrawOtherCurrencies: (() -> Void)?

    init(
        mint: PublicKey,
        container: Container,
        sessionContainer: SessionContainer,
        popStack: AppRouter.Stack,
        onWithdrawOtherCurrencies: (() -> Void)? = nil
    ) {
        let vm = WithdrawViewModel(container: container, sessionContainer: sessionContainer)
        if let stored = sessionContainer.session.balance(for: mint) {
            let rate = sessionContainer.ratesController.rateForBalanceCurrency()
            vm.setKind(for: stored.exchanged(with: rate))
        }
        self._viewModel = State(wrappedValue: vm)
        self.popStack = popStack
        self.onWithdrawOtherCurrencies = onWithdrawOtherCurrencies
    }

    var body: some View {
        WithdrawIntroScreen(
            onNext: viewModel.continueFromIntro,
            onWithdrawOtherCurrencies: onWithdrawOtherCurrencies
        )
        .withdrawSubstepDestinations(viewModel: viewModel)
        .onAppear {
            viewModel.pushSubstep = { step in
                router.pushAny(step)
            }
            viewModel.onComplete = {
                router.popToRoot(on: popStack)
            }
        }
    }
}
