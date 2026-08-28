//
//  SendAmountScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when a
/// send doesn't complete (errors stay put; not-found has already popped).
private struct SendDismissed: Error {}

/// Thin environment-reading wrapper that hands the session container to
/// ``SendAmountScreenContent``, whose `init` seeds the `@State` view model
/// synchronously from the contact being paid.
struct SendAmountScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let target: SendTarget

    var body: some View {
        SendAmountScreenContent(sessionContainer: sessionContainer, target: target)
    }
}

private struct SendAmountScreenContent: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var viewModel: SendAmountViewModel
    @State private var isShowingTokenSelection: Bool = false
    @State private var didSucceed: Bool = false

    private var maxLimit: ExchangedFiat {
        let rate = ratesController.rateForBalanceCurrency()
        guard let mint = viewModel.selectedBalance?.stored.mint,
              let balance = session.balance(for: mint) else {
            return ExchangedFiat.compute(
                onChainAmount: .zero(mint: .usdf),
                rate: rate,
                supplyQuarks: nil
            )
        }
        return balance.computeExchangedValue(with: rate)
    }

    // MARK: - Init -

    init(
        sessionContainer: SessionContainer,
        target: SendTarget
    ) {
        _viewModel = State(initialValue: SendAmountViewModel(
            sessionContainer: sessionContainer,
            target: target
        ))
    }

    // MARK: - Body -

    /// The tip floor when one applies, otherwise what's left to spend. A tip
    /// states its minimum up front and reports a breach through a dialog on
    /// submit, so the hint never reddens on that path.
    private var hint: EnterAmountHeader.Hint {
        if let minimum = viewModel.tipMinimum {
            .caption("\(minimum.formatted()) minimum")
        } else {
            .available(maxLimit)
        }
    }

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(maxLimit),
                actionEnabled: { _ in viewModel.canSend },
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $viewModel.enteredAmount,
                    hint: hint
                ))
            ) {
                SwipeControl(text: viewModel.isTipTarget ? "Swipe to Tip" : "Swipe to Send") {
                    switch await viewModel.sendAction() {
                    case .success:
                        didSucceed = true
                    case .recipientNotFound:
                        router.dismissSheet()
                        throw SendDismissed()
                    case .failed:
                        throw SendDismissed()
                    }
                }
            }
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                TokenSelectorButton(
                    selectedBalance: viewModel.selectedBalance,
                    action: { isShowingTokenSelection = true }
                )
                .id(viewModel.selectedBalance?.stored.mint)
            }
        }
        .onChange(of: viewModel.depositMint) { _, mint in
            guard let mint else { return }
            viewModel.depositMint = nil
            // Adding cash is a Wallet flow, so cross-stack to its Currency Info
            // (which auto-presents Buy) rather than burying it in the Send sheet —
            // `navigate` also keeps Buy from stacking a third level deep.
            router.navigate(to: .currencyInfoForDeposit(mint))
        }
        // Hold the success checkmark briefly, then dismiss back to the chat.
        // Tied to the view via `.task` so a dismissal during the hold cancels
        // the dismiss instead of firing it on a screen that's already gone.
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.delay(seconds: 1)
            guard !Task.isCancelled else { return }
            router.dismissSheet()
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(isPresented: $isShowingTokenSelection) { balance in
                viewModel.selectCurrencyAction(exchangedBalance: balance)
            }
        }
    }
}

