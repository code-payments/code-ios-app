//
//  ConvertAmountScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Amount entry for converting a currency into a chosen destination. Pushed
/// onto the host stack via `.convertCurrency(mint)`; the system back arrow
/// returns to the currency-info screen. Mirrors `BuyAmountScreen`'s pushable,
/// stack-native structure.
///
/// Thin environment-reading wrapper that hands the DI containers to
/// ``ConvertAmountScreenContent``, whose `init` seeds the `@State` view model
/// synchronously. `.id(mint)` rebuilds the content (and its view model) when the
/// mint changes.
struct ConvertAmountScreen: View {

    let mint: PublicKey

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        Group {
            if let sourceBalance = sessionContainer.session.balance(for: mint) {
                ConvertAmountScreenContent(
                    sourceBalance: sourceBalance,
                    session: sessionContainer.session,
                    ratesController: sessionContainer.ratesController
                )
            } else {
                // Convert is only reachable for held tokens, so a missing
                // balance means the wallet is mid-refresh — show nothing rather
                // than a broken keypad.
                Background(color: .backgroundMain) { EmptyView() }
            }
        }
        .id(mint)
    }
}

private struct ConvertAmountScreenContent: View {

    @State private var viewModel: ConvertAmountViewModel
    @State private var isShowingDestinationPicker = false

    @Environment(AppRouter.self) private var router

    init(sourceBalance: StoredBalance, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: ConvertAmountViewModel(
            sourceBalance: sourceBalance,
            session: session,
            ratesController: ratesController
        ))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .convert,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(viewModel.maxPossibleAmount),
                actionState: .constant(.normal),
                actionEnabled: { _ in viewModel.canPerformAction },
                action: { viewModel.showConfirmation(router: router) },
                accessory: AnyView(destinationSelector),
                header: AnyView(SwapAmountHeader(
                    enteredAmount: $viewModel.enteredAmount,
                    available: viewModel.maxPossibleAmount
                ))
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(viewModel.screenTitle)
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(for: ConvertFlowPath.self) { path in
            ConvertFlowDestinationView(path: path)
                .id(path)
        }
        .dialog(item: $viewModel.dialogItem)
        .sheet(isPresented: $isShowingDestinationPicker) {
            CurrencyPickerSheet(
                options: viewModel.destinationOptions,
                selectedMint: viewModel.destinationMint,
                onSelect: { mint in
                    viewModel.destinationMint = mint
                    isShowingDestinationPicker = false
                }
            )
        }
    }

    /// "Convert to [currency ▾]" — the destination selector that sits just above
    /// the keypad and opens the picker sheet.
    private var destinationSelector: some View {
        HStack(spacing: 12) {
            Text("Convert to")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)

            Spacer()

            Button {
                isShowingDestinationPicker = true
            } label: {
                HStack(spacing: 8) {
                    TokenIconWithName(
                        url: viewModel.destinationImageURL,
                        monogramID: viewModel.destinationMint.base58,
                        name: viewModel.destinationName
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("convert-destination-button")
        }
    }
}
