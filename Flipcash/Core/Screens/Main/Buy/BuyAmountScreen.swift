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
            // A buy targets a token the user may not hold, so there's no balance
            // to name it — fall back to the synced mint metadata before the
            // generic placeholder, so the confirmation and processing screens
            // read "Buying <name>" rather than "this currency".
            currencyName: sessionContainer.session.balance(for: mint)?.name
                ?? sessionContainer.session.storedMintMetadata(for: mint)?.name
                ?? "this currency",
            session: sessionContainer.session,
            ratesController: sessionContainer.ratesController
        )
        .id(mint)
    }

    /// Unwinds a finished pushed buy back to the screen that launched it — the gated chat, a
    /// pushed token screen, or the wallet — and closes the expanded card when the buy was launched
    /// from one, which sits over the wallet's root.
    static func finishPushedBuy(router: AppRouter, returningTo position: AppRouter.StackPosition?) {
        guard let position else {
            router.popToRoot()
            router.dismissExpandedCard()
            return
        }
        router.popTo(position)
        if position.depth == 0 {
            router.dismissExpandedCard()
        }
    }
}

private struct BuyAmountScreenContent: View {

    @State private var viewModel: BuyAmountViewModel
    @State private var isShowingPaymentPicker: Bool = false
    /// Where the pushed buy flow was launched from, captured on first appearance so finishing
    /// pops only the buy flow's own screens.
    @State private var launchPosition: AppRouter.StackPosition?

    @Environment(AppRouter.self) private var router
    /// True when this is the root of a presented sheet; false when pushed onto a
    /// host stack (Convert/Buy) where the system back arrow replaces Close.
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
                actionTitle: viewModel.actionTitle,
                accessory: AnyView(paymentSelector),
                header: AnyView(EnterAmountHeader(
                    enteredAmount: $viewModel.enteredAmount,
                    hint: .available(viewModel.maxPossibleAmount)
                ))
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
                // The presented buy sheet dismisses itself; the pushed buy flow
                // returns to the screen that launched it.
                .environment(\.dismissParentContainer, presentedAsSheetRoot
                    ? router.dismissSheet
                    : { BuyAmountScreen.finishPushedBuy(router: router, returningTo: launchPosition) })
                .id(path)
        }
        .sheet(isPresented: $isShowingPaymentPicker) {
            CurrencyPickerSheet(
                options: viewModel.paymentOptions,
                selectedMint: viewModel.paymentMint,
                onSelect: { mint in
                    viewModel.paymentMint = mint
                    isShowingPaymentPicker = false
                }
            )
        }
        .dialog(item: $viewModel.dialogItem)
        .onAppear {
            guard !presentedAsSheetRoot, launchPosition == nil else { return }
            launchPosition = router.positionBeneathTopmost()
        }
    }

    /// "Buy with [currency ▾]" — the payment-source selector shown just above
    /// the keypad; opens the picker sheet.
    private var paymentSelector: some View {
        HStack(spacing: 12) {
            Text("Buy with")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)

            Spacer()

            Button {
                isShowingPaymentPicker = true
            } label: {
                HStack(spacing: 8) {
                    TokenIconWithName(
                        url: viewModel.paymentImageURL,
                        monogramID: viewModel.paymentMint.base58,
                        name: viewModel.paymentName
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("get-payment-button")
        }
    }
}
