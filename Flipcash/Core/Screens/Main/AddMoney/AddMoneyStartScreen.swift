//
//  AddMoneyStartScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The `.addMoney` sheet — the "Select Method" deposit picker.
struct AddMoneyStartScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(VerificationCoordinator.self) private var verificationCoordinator

    @State private var flowMethod: DepositMethod?
    /// The up-front (v2) Coinbase verification sheet, presented before the amount
    /// screen; `nil` when not verifying.
    @State private var verificationViewModel: OnrampVerification?
    /// Set when verification passed while its sheet was still up — the amount
    /// flow opens once that sheet finishes dismissing (avoids a sheet collision).
    @State private var pendingCoinbaseAmount = false

    var body: some View {
        // The v2 tab-bar UI uses the richer "Add Money With" cards (Figma /
        // Android parity); v1 keeps the plain "Select Method" buttons.
        let isV2 = BetaFlags.shared.hasEnabled(.newUI)
        PartialSheet {
            VStack(spacing: 12) {
                HStack {
                    Text(isV2 ? "Add Money With" : "Select Method")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                }
                .padding(.vertical, 20)

                ForEach(Self.visibleMethods(hasCoinbaseOnramp: session.hasCoinbaseOnramp), id: \.self) { method in
                    if isV2 {
                        AddMoneyMethodRow(method: method) { select(method) }
                    } else {
                        AddMoneyMethodButton(method: method) { select(method) }
                    }
                }

                Button("Dismiss", action: { router.dismissSheet() })
                    .buttonStyle(.subtle)
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, isV2 ? 0 : 16)
        }
        .sheet(item: $flowMethod) { method in
            AddMoneyFlowSheet(method: method)
                .environment(\.dismissParentContainer, { router.dismissSheet() })
        }
        // Up-front (v2) Coinbase verification — presented directly over the
        // picker, before the amount flow opens.
        .sheet(item: $verificationViewModel.cancellingOnDismiss()) { vm in
            VerifyInfoScreen(viewModel: vm)
        }
        // Verification finished while its sheet was up: once it has dismissed,
        // open the amount flow (a short beat lets the sheet clear first).
        .onChange(of: verificationViewModel == nil) { _, isNil in
            guard isNil, pendingCoinbaseAmount else { return }
            pendingCoinbaseAmount = false
            let router = self.router
            Task { @MainActor in
                try? await Task.delay(milliseconds: 400)
                startFlow(.coinbase, using: router)
            }
        }
    }

    /// Chooses a deposit method.
    ///
    /// In the v2 UI the flow pushes onto the navigation stack the picker was
    /// launched from — matching the rest of the app — via `startFlow`, and a
    /// debit-card (Coinbase) deposit verifies phone/email first so no empty
    /// screen appears ahead of it (skipped over the buy sheet, already gated).
    ///
    /// The v1 UI keeps the sheet-based flow unchanged: the deposit opens as its
    /// own sheet, except over the buy sheet where it pushes as it always has.
    private func select(_ method: DepositMethod) {
        Analytics.addMoneyMethodSelected(method: method)
        let router = self.router

        guard BetaFlags.shared.hasEnabled(.newUI) else {
            if router.isAddMoneyOverBuy {
                dismissThenPush(AddMoneyFlowStep.method(method), using: router)
            } else {
                flowMethod = method
            }
            return
        }

        guard method == .coinbase, !router.isAddMoneyOverBuy else {
            startFlow(method, using: router)
            return
        }

        // A debit-card deposit verifies phone/email up front. With a host stack
        // the whole verification (intro → phone → email) pushes onto it ahead of
        // the deposit flow; without one (over the bare scanner) it falls back to
        // the sheet-based verification and sheet deposit flow.
        if let stack = router.addMoneyPushStack {
            startCoinbaseVerification(pushingOnto: stack, using: router)
        } else {
            verificationCoordinator.runGated(
                for: session,
                bind: { verificationViewModel = $0 },
                perform: {
                    // Already verified → `bind` never fired, so open immediately;
                    // otherwise wait for the verify sheet to dismiss.
                    if verificationViewModel == nil {
                        flowMethod = .coinbase
                    } else {
                        pendingCoinbaseAmount = true
                    }
                }
            )
        }
    }

    /// Enters the deposit flow for `method` in the v2 UI. When the picker sits
    /// over an existing navigation stack (the common case) it dismisses the
    /// picker and pushes the flow onto that stack so it reads like the rest of
    /// the app's navigation. With no stack beneath it — the no-balance gate
    /// opened over the bare scanner — it falls back to presenting the flow as
    /// its own sheet.
    private func startFlow(_ method: DepositMethod, using router: AppRouter) {
        if router.addMoneyPushStack != nil {
            dismissThenPush(AddMoneyFlowStep.method(method), using: router)
        } else {
            flowMethod = method
        }
    }

    /// Dismisses the picker, then pushes `value` onto the revealed stack once
    /// the sheet's dismiss animation has cleared. Pushing while the partial
    /// sheet is still sliding down runs the revealed stack's push animation at
    /// the same time, which flickers the new screen's back arrow — so the push
    /// waits for the sheet to settle (the app's dismiss-then-mutate pattern).
    private func dismissThenPush<H: Hashable>(_ value: H, using router: AppRouter) {
        router.dismissSheet()
        Task { @MainActor in
            try? await Task.sleep(for: AppRouter.dismissAnimationDuration)
            router.pushAny(value)
        }
    }

    /// v2 debit-card path with a host stack: pushes the verification flow
    /// (intro → phone → email) onto `stack`, then the deposit amount flow — one
    /// continuous push navigation. Skips straight to the deposit when the
    /// profile is already verified. On completion it dismisses the picker (if
    /// still up), unwinds the verification steps, and pushes the deposit.
    private func startCoinbaseVerification(pushingOnto stack: AppRouter.Stack, using router: AppRouter) {
        let baseline = router[stack].count
        verificationCoordinator.runGated(
            for: session,
            bind: { vm in
                guard let vm else { return }
                let first = vm.initialStep()
                vm.pushedHost = PushedVerificationHost(
                    rootStep: first,
                    push: { router.pushAny($0) },
                    // Everything above the depth the stack had before the flow
                    // started is the flow's own steps.
                    liveStepCount: { router[stack].count - baseline }
                )
                dismissThenPush(first, using: router)
            },
            perform: {
                if case .addMoney? = router.presentedSheet {
                    // Already verified: the picker is still up. Dismiss it and
                    // push the deposit once it clears (same anti-flicker beat).
                    dismissThenPush(AddMoneyFlowStep.method(.coinbase), using: router)
                } else {
                    // Verified via the pushed steps: unwind them and push the
                    // deposit inline on the already-visible stack.
                    let depth = router[stack].count
                    if depth > baseline {
                        router.popLast(depth - baseline, on: stack)
                    }
                    router.pushAny(AddMoneyFlowStep.method(.coinbase))
                }
            }
        )
    }

    /// The deposit methods to list — Pay (Coinbase) requires the onramp.
    static func visibleMethods(hasCoinbaseOnramp: Bool) -> [DepositMethod] {
        DepositMethod.allCases.filter { method in
            switch method {
            case .coinbase:
                return hasCoinbaseOnramp
            case .phantom, .otherWallet:
                return true
            }
        }
    }
}

private struct AddMoneyMethodButton: View {

    let method: DepositMethod
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch method {
            case .coinbase:
                Text("\u{F8FF}Pay")
                    .font(.body.bold())
            case .phantom:
                HStack(spacing: 4) {
                    Image.asset(.phantom)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Phantom")
                }
            case .otherWallet:
                Text("Other Wallet")
            }
        }
        .buttonStyle(.filled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// Stable identifier for UI tests — the Apple-glyph "Pay" label is
    /// brittle to match by text.
    private var accessibilityIdentifier: String {
        switch method {
        case .coinbase:    "apple-pay-method-button"
        case .phantom:     "phantom-method-button"
        case .otherWallet: "other-wallet-method-button"
        }
    }
}

/// The v2 "Add Money With" row: a titled/subtitled card with a trailing method
/// glyph (Figma / Android parity).
private struct AddMoneyMethodRow: View {

    let method: DepositMethod
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                icon
                    .foregroundStyle(Color.textMain)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var title: String {
        switch method {
        case .coinbase:    "Debit Card"
        case .phantom:     "Phantom"
        case .otherWallet: "Other Wallet"
        }
    }

    private var subtitle: String {
        switch method {
        case .coinbase:    "Deposit funds from your debit card"
        case .phantom:     "Deposit USDC from your Phantom wallet"
        case .otherWallet: "Deposit USDC from a crypto wallet"
        }
    }

    @ViewBuilder private var icon: some View {
        switch method {
        case .coinbase:
            Text("\u{F8FF}Pay")
                .font(.system(size: 22, weight: .semibold))
        case .phantom:
            Image.asset(.phantom)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        case .otherWallet:
            Image(systemName: "qrcode")
                .font(.system(size: 24, weight: .regular))
        }
    }

    private var accessibilityIdentifier: String {
        switch method {
        case .coinbase:    "apple-pay-method-button"
        case .phantom:     "phantom-method-button"
        case .otherWallet: "other-wallet-method-button"
        }
    }
}

// MARK: - Deposit flow

/// A step of the deposit flow. Normally pushed onto the stack the picker was
/// launched from (registered in `appRouterDestinations`); only when no such
/// stack exists is it hosted by the fallback `AddMoneyFlowSheet`. `.method` is
/// the per-method root.
enum AddMoneyFlowStep: Hashable {
    case method(DepositMethod)
    case phantomAmount
    case otherWalletAddress
    case otherWalletCurrencyList
    case otherWalletCurrencyAddress(PublicKey)
    case processing(AddMoneyProcessingInput)
}

/// Renders one deposit-flow step; `onStep` advances the hosting stack.
struct AddMoneyFlowDestination: View {

    let step: AddMoneyFlowStep
    let onStep: (AddMoneyFlowStep) -> Void

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        switch step {
        case .method(let method):
            AddMoneyFlowRoot(method: method, onStep: onStep)
        case .phantomAmount:
            AddMoneyAmountScreen(
                method: .phantom,
                session: sessionContainer.session,
                ratesController: sessionContainer.ratesController,
                onProceed: { onStep(.processing($0)) }
            )
        case .otherWalletAddress:
            DepositScreen.usdcDeposit(session: sessionContainer.session)
        case .otherWalletCurrencyList:
            DepositCurrencyListScreen(
                onSelect: { onStep(.otherWalletCurrencyAddress($0)) }
            )
        case .otherWalletCurrencyAddress(let mint):
            if let screen = DepositScreen.currencyDeposit(mint: mint, session: sessionContainer.session) {
                screen
            }
        case .processing(let input):
            AddMoneyProcessingScreen(input: input)
        }
    }
}

/// Fallback host for the deposit flow when the picker has no navigation stack
/// beneath it to push onto (the no-balance gate opened over the bare scanner).
/// Presents the flow as its own sheet, driving a local navigation path.
private struct AddMoneyFlowSheet: View {

    let method: DepositMethod

    @State private var path: [AddMoneyFlowStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            AddMoneyFlowDestination(step: .method(method), onStep: { path.append($0) })
                // The flow's per-method root is this sheet's root — it has no
                // back arrow, so it owns the Close button.
                .environment(\.presentedAsSheetRoot, true)
                .navigationDestination(for: AddMoneyFlowStep.self) { step in
                    AddMoneyFlowDestination(step: step, onStep: { path.append($0) })
                }
        }
    }
}

private struct AddMoneyFlowRoot: View {

    let method: DepositMethod
    let onStep: (AddMoneyFlowStep) -> Void

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismissParentContainer) private var dismissParentContainer
    @Environment(\.presentedAsSheetRoot) private var presentedAsSheetRoot

    var body: some View {
        Group {
            switch method {
            case .coinbase:
                AddMoneyAmountScreen(
                    method: .coinbase,
                    session: sessionContainer.session,
                    ratesController: sessionContainer.ratesController,
                    onProceed: { onStep(.processing($0)) }
                )
            case .phantom:
                PhantomEducationScreen(onConnected: { onStep(.phantomAmount) })
            case .otherWallet:
                USDCDepositEducationScreen(
                    title: "Other Wallet",
                    onNext: { onStep(.otherWalletAddress) },
                    onDepositOtherCurrencies: { onStep(.otherWalletCurrencyList) }
                )
            }
        }
        .toolbar {
            // Pushed onto a stack the flow already has a back arrow; only the
            // sheet-root presentation needs a Close button.
            if presentedAsSheetRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton(action: dismissParentContainer)
                }
            }
        }
    }
}
