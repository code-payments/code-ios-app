//
//  BuyAmountScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Amount entry for buying a currency. The caller provides the surrounding
/// `NavigationStack` — the buy sheet wraps it, the pushed `.buyCurrency`
/// destination uses the active one.
///
/// Thin environment-reading wrapper that hands the DI containers to
/// ``BuyAmountScreenContent``, whose `init` seeds the `@State` view model
/// synchronously. `.id(mint)` rebuilds the content (and its view model) when the
/// mint changes.
struct BuyAmountScreen: View {

    let mint: PublicKey

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        BuyAmountScreenContent(
            mint: mint,
            currencyName: sessionContainer.session.balance(for: mint)?.name ?? "this currency",
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        .id(mint)
    }
}

private struct BuyAmountScreenContent: View {

    @State private var viewModel: BuyAmountViewModel
    @State private var isShowingCurrencySelection: Bool = false

    @Environment(AppRouter.self) private var router
    @Environment(RatesController.self) private var ratesController
    /// True when this is the root of a presented sheet; false when pushed onto a
    /// host stack (new-UI Convert/Get) where the system back arrow replaces Close.
    @Environment(\.presentedAsSheetRoot) private var presentedAsSheetRoot

    init(mint: PublicKey, currencyName: String, session: Session, ratesController: RatesController) {
        self._viewModel = State(initialValue: BuyAmountViewModel(
            mint: mint,
            currencyName: currencyName,
            session: session,
            ratesController: ratesController
        ))
    }

    private var isDismissBlocked: Bool {
        // Any pushed sub-flow screen (processing) — destination-level
        // `interactiveDismissDisabled(true)` does NOT propagate through the
        // nested-sheet binding, so gate at the NavigationStack root by
        // checking the path is non-empty.
        !router[.buy].isEmpty
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        Background(color: .backgroundMain) {
            EnterAmountView(
                mode: .buy,
                enteredAmount: $viewModel.enteredAmount,
                subtitle: .balanceWithLimit(viewModel.maxPossibleAmount),
                // Submission moved to the Buy summary; the amount step's
                // button never leaves `.normal`.
                actionState: .constant(.normal),
                actionEnabled: { viewModel.actionEnabled($0) },
                action: { viewModel.primaryAction(router: router) },
                currencySelectionAction: showCurrencySelection,
                actionTitle: viewModel.actionTitle
            )
            .foregroundStyle(.textMain)
            .padding(20)
        }
        .ignoresSafeArea(.keyboard)
        .navigationTitle(viewModel.screenTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            // Only the sheet-root presentation gets a Close button; a pushed
            // instance relies on the system back arrow.
            if presentedAsSheetRoot && !isDismissBlocked {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: router.dismissSheet)
                }
            }
        }
        .interactiveDismissDisabled(isDismissBlocked)
        .navigationDestination(for: BuyFlowPath.self) { path in
            // Env value must be set on the destination view itself — modifiers
            // on the source view don't propagate to navigation destinations
            // (they live in a separate SwiftUI context). `.id(path)` forces a
            // fresh view identity per path value so init-seeded @State can't
            // survive a same-depth value swap (the DestinationView convention).
            BuyFlowDestinationView(path: path)
                .environment(\.dismissParentContainer, router.dismissSheet)
                .id(path)
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(ratesController: ratesController)
        }
    }

    private func showCurrencySelection() {
        isShowingCurrencySelection.toggle()
    }
}
