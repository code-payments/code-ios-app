//
//  AddMoneyStartScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The `.addMoney` sheet — the "Select Method" deposit picker.
struct AddMoneyStartScreen: View {

    let context: AddMoneyContext

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    @State private var flowMethod: DepositMethod?

    var body: some View {
        PartialSheet {
            VStack(spacing: 12) {
                HStack {
                    Text("Select Method")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                }
                .padding(.vertical, 20)

                ForEach(Self.visibleMethods(hasCoinbaseOnramp: session.hasCoinbaseOnramp), id: \.self) { method in
                    AddMoneyMethodButton(method: method) { select(method) }
                }

                Button("Dismiss", action: { router.dismissSheet() })
                    .buttonStyle(.subtle)
            }
            .padding()
        }
        .sheet(item: $flowMethod) { method in
            AddMoneyFlowSheet(method: method)
                .environment(\.dismissParentContainer, { router.dismissSheet() })
        }
    }

    /// Over the buy amount sheet the deposit flow pushes onto that sheet's
    /// stack; everywhere else it opens as its own sheet on top.
    private func select(_ method: DepositMethod) {
        Analytics.addMoneyMethodSelected(method: method)
        if router.isAddMoneyOverBuy {
            router.dismissSheet()
            router.pushAny(AddMoneyFlowStep.method(method))
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
