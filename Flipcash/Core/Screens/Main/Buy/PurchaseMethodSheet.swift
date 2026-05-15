//
//  PurchaseMethodSheet.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Half-sheet picker shown when a funding intent cannot be filled from the
/// USDF reserve alone. Shared by buy-existing and currency-launch flows via
/// `PaymentOperation`. Callers compose the `sources` array to control which
/// methods render — buy passes all three, launch omits `.otherWallet`.
struct PurchaseMethodSheet: View {

    let operation: PaymentOperation
    let sources: [Method]
    /// Caller-provided dispatch for the Apple Pay path. Invoked with the
    /// payment payload so the caller (BuyAmountViewModel / wizard) can
    /// construct + start a `CoinbaseFundingOperation` on its owning
    /// viewmodel after running the verification gate.
    let applePayAction: (PaymentOperation) -> Void
    /// Caller-provided dispatch for the Phantom path — invoked with the
    /// payment payload so the caller can construct + start a
    /// `PhantomFundingOperation` on its owning viewmodel. The picker
    /// dismisses itself before this fires (animations don't stack with the
    /// destination push the operation drives via `FundingFlowHost`).
    let phantomAction: (PaymentOperation) -> Void
    let onDismiss: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    enum Method: Hashable {
        case applePay
        case phantom
        case otherWallet
    }

    var body: some View {
        PartialSheet {
            VStack(spacing: 12) {
                HStack {
                    Text("Select Purchase Method")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                }
                .padding(.vertical, 20)

                // Apple Pay is hidden if the caller didn't request it OR the
                // session can't actually use Coinbase.
                ForEach(visibleSources, id: \.self) { method in
                    MethodButton(
                        method: method,
                        operation: operation,
                        applePayAction: applePayAction,
                        phantomAction: phantomAction,
                        onDismiss: onDismiss
                    )
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.subtle)
            }
            .padding()
        }
    }

    private var visibleSources: [Method] {
        Self.visibleSources(from: sources, session: session)
    }

    /// Pure function exposing the visibility filter so it can be unit-tested
    /// without instantiating a SwiftUI view. Apple Pay drops out when the
    /// session can't actually use Coinbase, regardless of whether the caller
    /// requested it.
    static func visibleSources(from sources: [Method], session: Session) -> [Method] {
        sources.filter { method in
            switch method {
            case .applePay:
                return session.hasCoinbaseOnramp
            case .phantom, .otherWallet:
                return true
            }
        }
    }
}

private struct MethodButton: View {
    let method: PurchaseMethodSheet.Method
    let operation: PaymentOperation
    let applePayAction: (PaymentOperation) -> Void
    let phantomAction: (PaymentOperation) -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch method {
        case .applePay:
            ApplePayMethodButton(
                operation: operation,
                applePayAction: applePayAction,
                onDismiss: onDismiss
            )
        case .phantom:
            PhantomMethodButton(
                operation: operation,
                phantomAction: phantomAction,
                onDismiss: onDismiss
            )
        case .otherWallet:
            OtherWalletMethodButton(onDismiss: onDismiss)
        }
    }
}

/// Dismisses the sheet, then waits for the system's dismiss animation
/// before invoking `action`. Without the wait, pushing onto a navigation
/// stack while the sheet is still mid-dismiss racing causes SwiftUI to
/// drop the push.
@MainActor
private func dismissThenDispatch(
    onDismiss: () -> Void,
    action: @escaping @MainActor @Sendable () -> Void
) {
    onDismiss()
    Task { @MainActor in
        try? await Task.sleep(for: AppRouter.dismissAnimationDuration)
        action()
    }
}

private struct ApplePayMethodButton: View {
    let operation: PaymentOperation
    let applePayAction: (PaymentOperation) -> Void
    let onDismiss: () -> Void

    @Environment(Session.self) private var session

    var body: some View {
        Button {
            // Coinbase Onramp rejects USD purchases under the minimum — gate
            // before the Apple Pay sheet round-trip. Use the USDF (1:1 USD)
            // value since `nativeAmount` is in the user's display currency.
            let minimumUSD = OnrampCoordinator.minimumPurchaseUSD
            guard operation.displayAmount.usdfValue.value >= minimumUSD else {
                let minimum = FiatAmount.usd(minimumUSD)
                    .converting(to: operation.displayAmount.currencyRate)
                    .formatted()
                session.dialogItem = .applePayMinimumPurchase(minimum: minimum)
                return
            }
            Analytics.buttonTapped(name: .buyWithCoinbase)
            let operation = self.operation
            dismissThenDispatch(onDismiss: onDismiss) {
                applePayAction(operation)
            }
        } label: {
            Text("\u{F8FF}Pay")
                .font(.body.bold())
        }
        .buttonStyle(.filled)
        .accessibilityIdentifier("apple-pay-method-button")
    }
}

private struct PhantomMethodButton: View {
    let operation: PaymentOperation
    let phantomAction: (PaymentOperation) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button {
            Analytics.buttonTapped(name: .buyWithPhantom)
            let operation = self.operation
            // Dismiss the picker first; `phantomAction` constructs the
            // operation on the caller's viewmodel and `FundingFlowHost`
            // pushes the education screen on the operation's first state
            // transition.
            dismissThenDispatch(onDismiss: onDismiss) {
                phantomAction(operation)
            }
        } label: {
            HStack(spacing: 4) {
                Image.asset(.phantom)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Phantom")
            }
        }
        .buttonStyle(.filled)
    }
}

private struct OtherWalletMethodButton: View {
    let onDismiss: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        Button("Other Wallet") {
            dismissThenDispatch(onDismiss: onDismiss) { [router] in
                router.push(.usdcDepositEducation)
            }
        }
        .buttonStyle(.filled)
    }
}
