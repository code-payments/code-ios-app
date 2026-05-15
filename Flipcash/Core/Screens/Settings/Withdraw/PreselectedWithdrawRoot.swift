//
//  PreselectedWithdrawRoot.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Withdraw flow entry point that skips the "Select Currency" picker.
/// Configures `WithdrawViewModel` with the mint before `@State` boxes it,
/// so the intro screen renders with `kind` already populated.
struct PreselectedWithdrawRoot: View {

    @Environment(AppRouter.self) private var router
    @State private var viewModel: WithdrawViewModel

    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer) {
        let vm = WithdrawViewModel(container: container, sessionContainer: sessionContainer)
        if let stored = sessionContainer.session.balance(for: mint) {
            let rate = sessionContainer.ratesController.rateForBalanceCurrency()
            vm.selectCurrency(stored.exchanged(with: rate))
        }
        self._viewModel = State(wrappedValue: vm)
    }

    var body: some View {
        WithdrawIntroScreen()
            .withdrawSubstepDestinations(viewModel: viewModel)
            .onAppear {
                viewModel.pushSubstep = { step in
                    router.pushAny(step)
                }
                viewModel.onComplete = {
                    router.popToRoot(on: .balance)
                }
            }
    }
}
