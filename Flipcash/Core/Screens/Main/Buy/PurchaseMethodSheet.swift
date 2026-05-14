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
    /// Callers whose Apple Pay flow needs preflight work before invoking
    /// `OnrampCoordinator.start(_:amount:)` provide this override. The buy
    /// flow passes `nil` so the picker dispatches directly.
    let applePayAction: (() -> Void)?
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
    let applePayAction: (() -> Void)?
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
            PhantomMethodButton(operation: operation, onDismiss: onDismiss)
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
    let applePayAction: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(OnrampCoordinator.self) private var coordinator
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
            if let applePayAction {
                // Caller-provided dispatch — used by the launch flow which
                // needs to run preflight (launchCurrency) before starting
                // the coordinator.
                dismissThenDispatch(onDismiss: onDismiss) {
                    applePayAction()
                }
                return
            }
            // Default buy dispatch.
            guard case .buy(let payload) = operation else {
                // Defensive — launch should always pass applePayAction.
                return
            }
            let amount = payload.amount
            let mint = payload.mint
            let displayName = payload.currencyName
            dismissThenDispatch(onDismiss: onDismiss) { [coordinator] in
                coordinator.start(.buy(mint: mint, displayName: displayName), amount: amount)
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
    let onDismiss: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            Analytics.buttonTapped(name: .buyWithPhantom)
            let operation = self.operation
            // Just push the education destination — the Phantom connect
            // deeplink fires from the education screen's "Connect Your
            // Phantom Wallet" button, not here. This keeps the connect
            // prompt off-screen until the user has read the education copy.
            dismissThenDispatch(onDismiss: onDismiss) { [router] in
                router.push(.phantomEducation(operation))
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
