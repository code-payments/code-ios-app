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

struct SendAmountScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var viewModel: SendAmountViewModel
    @State private var isShowingCurrencySelection: Bool = false
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
        contact: ResolvedContact
    ) {
        _viewModel = State(initialValue: SendAmountViewModel(
            sessionContainer: sessionContainer,
            contact: contact
        ))
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(maxLimit),
                actionEnabled: { _ in viewModel.canSend },
                currencySelectionAction: { isShowingCurrencySelection.toggle() }
            ) {
                SwipeControl(text: "Swipe to Send") {
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
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, -40)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(ratesController: ratesController)
            }
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

// MARK: - Token selector -

private struct TokenSelectorButton: View {

    let selectedBalance: ExchangedBalance?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                CurrencyLabel(
                    imageURL: selectedBalance?.stored.imageURL,
                    name: selectedBalance?.stored.name ?? "",
                    amount: nil
                )

                Image.system(.chevronDown)
                    .font(.default(size: 12, weight: .bold))
                    .foregroundStyle(.textMain)
            }
        }
    }
}
