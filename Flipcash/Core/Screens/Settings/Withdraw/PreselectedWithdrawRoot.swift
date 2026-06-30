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
///
/// Thin environment-reading wrapper that hands the DI containers to
/// ``PreselectedWithdrawRootContent``, whose `init` builds and synchronously
/// configures (`setKind`) the `@State` withdraw view model from the preselected
/// mint.
struct PreselectedWithdrawRoot: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    let mint: PublicKey
    let onComplete: () -> Void
    var onWithdrawOtherCurrencies: (() -> Void)? = nil

    var body: some View {
        PreselectedWithdrawRootContent(
            mint: mint,
            container: container,
            sessionContainer: sessionContainer,
            onComplete: onComplete,
            onWithdrawOtherCurrencies: onWithdrawOtherCurrencies
        )
    }
}

private struct PreselectedWithdrawRootContent: View {

    @Environment(AppRouter.self) private var router
    @State private var viewModel: WithdrawViewModel

    private let onComplete: () -> Void
    private let onWithdrawOtherCurrencies: (() -> Void)?

    init(
        mint: PublicKey,
        container: Container,
        sessionContainer: SessionContainer,
        onComplete: @escaping () -> Void,
        onWithdrawOtherCurrencies: (() -> Void)? = nil
    ) {
        let vm = WithdrawViewModel(container: container, sessionContainer: sessionContainer)
        if let stored = sessionContainer.session.balance(for: mint) {
            let rate = sessionContainer.ratesController.rateForBalanceCurrency()
            vm.setKind(for: stored.exchanged(with: rate))
        }
        self._viewModel = State(wrappedValue: vm)
        self.onComplete = onComplete
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
            viewModel.onComplete = onComplete
        }
    }
}
