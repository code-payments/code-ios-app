//
//  AddMoneyStartScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The `.addMoney` sheet — the "Select Method" deposit picker, matching the
/// app's `PurchaseMethodSheet` layout. Reached from the "No Balance Yet"
/// `Dialog`'s Add Money action (gated flows) or directly from the Wallet and
/// Settings Add Money buttons. Picking a method opens the deposit flow as a
/// **sheet on top** (amount entry → the blocking "Adding Money" screen for
/// Coinbase/Phantom; the deposit-address screen for Other Wallet).
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
                // The deposit flow on top of the picker. The close button /
                // processing "OK" tears down the whole Add Money sheet back to
                // the originating screen.
                .environment(\.dismissParentContainer, { router.dismissSheet() })
        }
    }

    /// Over the buy amount sheet, selection continues INSIDE that sheet: the
    /// options pop and the deposit flow pushes onto the buy stack, so the
    /// keypad is navigated away and the sheet's close lands on the currency
    /// screen. Everywhere else the flow opens as its own sheet on top.
    private func select(_ method: DepositMethod) {
        if router.isAddMoneyOverBuy {
            router.dismissSheet()
            router.pushAny(AddMoneyFlowStep.method(method))
        } else {
            flowMethod = method
        }
    }

    /// Pure visibility filter — Pay (Coinbase) drops out unless the
    /// session can actually use the onramp. Exposed statically so it is
    /// unit-testable without building the view.
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

    /// The Apple-glyph "Pay" label is brittle to match by text, so
    /// each row carries a stable identifier the UI tests key off.
    private var accessibilityIdentifier: String {
        switch method {
        case .coinbase:    "apple-pay-method-button"
        case .phantom:     "phantom-method-button"
        case .otherWallet: "other-wallet-method-button"
        }
    }
}

// MARK: - Deposit flow (new full sheet on top of the prompt)

/// A step of the deposit flow. `.method` is the per-method root (Coinbase
/// enters an amount; Phantom starts at its education/connect screen; Other
/// Wallet starts at the USDC education screen). Later steps follow: the
/// deposit-address screens for Other Wallet, and the blocking "Adding Money"
/// screen for Coinbase/Phantom. Hosted either by `AddMoneyFlowSheet` (its own
/// sheet over the options) or pushed onto the buy sheet's stack when the
/// options were raised from the buy amount screen.
enum AddMoneyFlowStep: Hashable {
    case method(DepositMethod)
    case phantomAmount
    case otherWalletAddress
    case otherWalletCurrencyList
    case otherWalletCurrencyAddress(PublicKey)
    case processing(AddMoneyProcessingInput)
}

/// Renders one deposit-flow step. Shared by the standalone flow sheet (steps
/// drive its local path) and the buy sheet's stack (steps push via the
/// router), so both hosts stay in lockstep.
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
            // Authority pubkey, NOT the derived USDC ATA — the same
            // address the Wallet's Other Wallet path shows. See the
            // `.usdcDepositAddress` destination for why.
            DepositScreen(
                address: sessionContainer.session.owner.authorityPublicKey.base58,
                name: "USDC"
            )
        case .otherWalletCurrencyList:
            // The education screen's "Deposit Other Flipcash Currencies"
            // footer. Selection drives the hosting stack directly rather
            // than the top-level router.
            DepositCurrencyListScreen(
                onSelect: { onStep(.otherWalletCurrencyAddress($0)) }
            )
        case .otherWalletCurrencyAddress(let mint):
            // Mirrors the `.depositAddress(mint)` destination: the
            // currency's derived deposit ATA, not the USDC authority.
            if let balance = sessionContainer.session.balance(for: mint),
               let vmAuthority = balance.vmAuthority {
                DepositScreen(
                    address: sessionContainer.session.owner.use(
                        mint: mint,
                        timeAuthority: vmAuthority
                    ).depositPublicKey.base58,
                    name: mint == .usdf ? balance.symbol : balance.name
                )
            }
        case .processing(let input):
            AddMoneyProcessingScreen(input: input)
        }
    }
}

/// The full-height deposit flow, presented as its own sheet on top of the
/// content-sized prompt. Coinbase enters an amount and pushes the blocking
/// "Adding Money" screen; Phantom connects first, then enters an amount; Other
/// Wallet shows the USDC deposit address.
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
                // Mirrors the Wallet's Other Wallet flow: the USDC education
                // screen, then the deposit-address screen on Next (or the
                // currency list via the footer).
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
