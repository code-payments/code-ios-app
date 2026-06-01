//
//  SendAmountScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SendAmountScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var viewModel: SendAmountViewModel
    @State private var isShowingCurrencySelection: Bool = false
    @State private var isShowingTokenSelection: Bool = false

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
            switch viewModel.state {
            case .ready, .submitting:
                EnterAmountView(
                    mode: .currency,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .balanceWithLimit(maxLimit),
                    actionState: $viewModel.actionState,
                    actionEnabled: { _ in viewModel.canSend },
                    action: {
                        Task {
                            switch await viewModel.sendAction() {
                            case .stay:
                                break
                            case .recipientNotFound:
                                router.popTopmost()
                            }
                        }
                    },
                    currencySelectionAction: { isShowingCurrencySelection.toggle() }
                )
                .foregroundStyle(.textMain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, -40)
                .sheet(isPresented: $isShowingCurrencySelection) {
                    CurrencySelectionScreen(ratesController: ratesController)
                }
            case .succeeded(let amount):
                SendSuccessView(
                    amount: amount,
                    recipientDisplayName: viewModel.recipientDisplayName
                )
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
            router.push(.currencyInfoForDeposit(mint))
        }
        .task(id: viewModel.state) {
            guard case .succeeded = viewModel.state else { return }
            try? await Task.sleep(for: .seconds(2.5))
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

// MARK: - Success view -

private struct SendSuccessView: View {

    let amount: ExchangedFiat
    let recipientDisplayName: String?

    var body: some View {
        VStack(spacing: 16) {
            Image.system(.circleCheck)
                .font(.default(size: 64, weight: .regular))
                .foregroundStyle(.textMain)

            VStack(spacing: 8) {
                Text("Sent \(amount.nativeAmount.formatted())")
                    .font(.appDisplaySmall)
                    .foregroundStyle(.textMain)
                    .multilineTextAlignment(.center)

                if let recipientDisplayName {
                    Text("to \(recipientDisplayName)")
                        .font(.appTextMedium)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
