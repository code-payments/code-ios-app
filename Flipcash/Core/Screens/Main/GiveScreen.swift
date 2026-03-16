//
//  GiveScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Amount entry screen for giving cash to another user.
///
/// This view does not own a `NavigationStack` — the caller is responsible
/// for providing one. When presented as a **sheet** (e.g. from `ScanScreen`),
/// wrap it in a `NavigationStack` and add a close button. When **pushed**
/// (e.g. from `CurrencyInfoScreen`), use it directly inside the existing
/// navigation stack.
///
/// On completion (`viewModel.isPresented` becomes `false`), this view calls
/// `dismissParentContainer()` so that any ancestor sheet is dismissed in a
/// single animation before the bill appears.
struct GiveScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    @ObservedObject private var viewModel: GiveViewModel

    @State private var isShowingCurrencySelection: Bool = false
    @State private var isShowingTokenSelection: Bool = false

    @State private var dialogItem: DialogItem?

    @Environment(\.dismissParentContainer) private var dismissParentContainer

    private var maxLimit: ExchangedFiat {
        let entryRate = ratesController.rateForEntryCurrency()
        let zero      = try! ExchangedFiat(underlying: 0, rate: entryRate, mint: .usdf)

        guard let mint = viewModel.selectedBalance?.stored.mint else {
            return zero
        }

        guard let balance = session.balance(for: mint) else {
            return zero
        }

        return balance.computeExchangedValue(with: entryRate)
    }

    // MARK: - Init -

    init(viewModel: GiveViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .currency,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(maxLimit),
                actionState: $viewModel.actionState,
                actionEnabled: { _ in
                    viewModel.canGive
                },
                action: nextAction,
                currencySelectionAction: showCurrencySelection
            )
            .foregroundColor(.textMain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, -40)
            .sheet(isPresented: $isShowingCurrencySelection) {
                CurrencySelectionScreen(
                    isPresented: $isShowingCurrencySelection,
                    kind: .entry,
                    ratesController: ratesController
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
        .navigationDestination(item: $viewModel.depositMint) { mint in
            CurrencyInfoScreen(
                mint: mint,
                container: viewModel.container,
                sessionContainer: viewModel.sessionContainer,
                showFundingOnAppear: true
            )
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(
                isPresented: $isShowingTokenSelection,
                kind: .give { balance in
                    viewModel.selectCurrencyAction(exchangedBalance: balance)
                },
                fixedRate: nil,
            )
        }
        .dialog(item: $dialogItem)
        .dialog(item: $viewModel.dialogItem)
        .onChange(of: viewModel.isPresented) { _, isPresented in
            if !isPresented {
                dismissParentContainer()
            }
        }
    }

    // MARK: - Actions -

    private func nextAction() {
        viewModel.giveAction()
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}

// MARK: - TokenSelectorButton -

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
                    .foregroundColor(.textMain)
            }
        }
    }
}
