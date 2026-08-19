//
//  WithdrawFlowRoot.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-13.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Entry point for the withdraw flow. With no preselected mint it starts on the
/// currency picker (every balance, Dollars included). With a preselected mint it
/// skips the picker: Dollars (USDF) lands on the "Withdraw as USDC" intro, any
/// other currency lands directly on the amount screen.
///
/// Thin environment-reading wrapper that hands the DI containers to
/// ``WithdrawFlowRootContent``, whose `init` builds and synchronously configures
/// the `@State` withdraw view model and resolves the initial step.
struct WithdrawFlowRoot: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    var preselectedMint: PublicKey? = nil
    let onComplete: () -> Void

    var body: some View {
        WithdrawFlowRootContent(
            preselectedMint: preselectedMint,
            container: container,
            sessionContainer: sessionContainer,
            onComplete: onComplete
        )
    }
}

private struct WithdrawFlowRootContent: View {

    @Environment(AppRouter.self) private var router
    @State private var viewModel: WithdrawViewModel

    private let initialPath: WithdrawNavigationPath
    private let onComplete: () -> Void

    init(
        preselectedMint: PublicKey?,
        container: Container,
        sessionContainer: SessionContainer,
        onComplete: @escaping () -> Void
    ) {
        let vm = WithdrawViewModel(container: container, sessionContainer: sessionContainer)

        if let mint = preselectedMint, let stored = sessionContainer.session.balance(for: mint) {
            let rate = sessionContainer.ratesController.rateForBalanceCurrency()
            vm.setKind(for: stored.exchanged(with: rate))
            // Dollars detours through the USDC intro; any other currency skips
            // straight to the amount screen.
            initialPath = mint == .usdf ? .intro : .enterAmount
        } else {
            initialPath = .picker
        }

        self._viewModel = State(wrappedValue: vm)
        self.onComplete = onComplete
    }

    var body: some View {
        WithdrawSubstepDestination(path: initialPath, viewModel: viewModel)
            .withdrawSubstepDestinations(viewModel: viewModel)
            .onAppear {
                viewModel.pushSubstep = { step in
                    router.pushAny(step)
                }
                viewModel.onComplete = onComplete
            }
    }
}
