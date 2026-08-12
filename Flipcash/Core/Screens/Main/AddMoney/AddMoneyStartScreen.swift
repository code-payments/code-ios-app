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
            Task { @MainActor in
                try? await Task.delay(milliseconds: 400)
                flowMethod = .coinbase
            }
        }
    }

    /// Over the buy amount sheet the deposit flow pushes onto that sheet's
    /// stack; everywhere else it opens as its own sheet on top. In v2 a
    /// debit-card (Coinbase) deposit verifies phone/email first — the amount
    /// flow opens only once verification passes (immediately if already
    /// verified), so no empty sheet appears ahead of it.
    private func select(_ method: DepositMethod) {
        Analytics.addMoneyMethodSelected(method: method)
        if router.isAddMoneyOverBuy {
            router.dismissSheet()
            router.pushAny(AddMoneyFlowStep.method(method))
            return
        }
        if method == .coinbase, BetaFlags.shared.hasEnabled(.newUI) {
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
        } else {
            flowMethod = method
        }
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

// MARK: - Deposit flow (new full sheet on top of the prompt)

/// A step of the deposit flow, hosted by `AddMoneyFlowSheet` or pushed onto
/// the buy sheet's stack. `.method` is the per-method root.
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

/// The deposit flow presented as its own sheet, driving a local
/// navigation path.
private struct AddMoneyFlowSheet: View {

    let method: DepositMethod

    @State private var path: [AddMoneyFlowStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            AddMoneyFlowDestination(step: .method(method), onStep: { path.append($0) })
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
            ToolbarItem(placement: .topBarTrailing) {
                CloseButton(action: dismissParentContainer)
            }
        }
    }
}
