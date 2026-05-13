//
//  PurchaseMethodSheet.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Half-sheet picker shown when a buy intent cannot be filled from the USDF
/// reserve alone. Lists the funding methods available to the current user
/// (Apple Pay via Coinbase, Phantom, generic Other Wallet) and routes each
/// selection into the corresponding sub-flow on the buy stack.
struct PurchaseMethodSheet: View {

    let context: PurchaseMethodContext
    let onDismiss: () -> Void

    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session

    enum Method: Hashable {
        case applePay
        case phantom
        case otherWallet
    }

    /// Source of truth for which rows render. Pure function so visibility can
    /// be unit-tested without instantiating SwiftUI views.
    static func methods(forSession session: Session) -> [Method] {
        var result: [Method] = []
        if session.hasCoinbaseOnramp {
            result.append(.applePay)
        }
        result.append(.phantom)
        result.append(.otherWallet)
        return result
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

                ForEach(Self.methods(forSession: session), id: \.self) { method in
                    MethodButton(
                        method: method,
                        context: context,
                        onDismiss: onDismiss,
                        router: router
                    )
                }

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.subtle)
            }
            .padding()
        }
    }
}

/// Dispatch wrapper so the parent body can `ForEach` over `methods(forSession:)`
/// and have a single source of truth for which rows render. The concrete row
/// structs below own the visual + side-effect details.
private struct MethodButton: View {
    let method: PurchaseMethodSheet.Method
    let context: PurchaseMethodContext
    let onDismiss: () -> Void
    let router: AppRouter

    var body: some View {
        switch method {
        case .applePay:
            ApplePayMethodButton(context: context, onDismiss: onDismiss)
        case .phantom:
            PhantomMethodButton(context: context, onDismiss: onDismiss, router: router)
        case .otherWallet:
            OtherWalletMethodButton(onDismiss: onDismiss, router: router)
        }
    }
}

/// Dismisses the sheet, then waits for the system's dismiss animation
/// before invoking `action`. Without the wait, pushing onto the buy
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
    let context: PurchaseMethodContext
    let onDismiss: () -> Void

    @Environment(OnrampCoordinator.self) private var coordinator
    @Environment(Session.self) private var session

    var body: some View {
        Button {
            // Coinbase Onramp rejects USD purchases under the minimum — gate
            // before the Apple Pay sheet round-trip. Use the USDF (1:1 USD)
            // value since `nativeAmount` is in the user's display currency.
            let minimumUSD = OnrampCoordinator.minimumPurchaseUSD
            guard context.amount.usdfValue.value >= minimumUSD else {
                let minimum = FiatAmount.usd(minimumUSD)
                    .converting(to: context.amount.currencyRate)
                    .formatted()
                session.dialogItem = .applePayMinimumPurchase(minimum: minimum)
                return
            }
            Analytics.buttonTapped(name: .buyWithCoinbase)
            let mint = context.mint
            let displayName = context.currencyName
            let amount = context.amount
            dismissThenDispatch(onDismiss: onDismiss) { [coordinator] in
                coordinator.start(.buy(mint: mint, displayName: displayName), amount: amount)
            }
        } label: {
            Text("\u{F8FF}Pay")
                .font(.body.bold())
        }
        .buttonStyle(.filled)
    }
}

private struct PhantomMethodButton: View {
    let context: PurchaseMethodContext
    let onDismiss: () -> Void
    let router: AppRouter

    @Environment(WalletConnection.self) private var walletConnection

    var body: some View {
        Button {
            Analytics.buttonTapped(name: .buyWithPhantom)
            // Skip the education screen when a Phantom session already exists
            // — the user has connected before and just needs to confirm. The
            // education screen's auto-advance latch breaks on pop-back from
            // confirm, which would otherwise surface a stale "Connect Your
            // Phantom Wallet" CTA to an already-connected user.
            let nextStep: BuyFlowPath = walletConnection.isConnected
                ? .phantomConfirm(mint: context.mint, amount: context.amount)
                : .phantomEducation(mint: context.mint, amount: context.amount)
            dismissThenDispatch(onDismiss: onDismiss) { [router] in
                router.pushAny(nextStep)
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
    let router: AppRouter

    var body: some View {
        Button("Other Wallet") {
            dismissThenDispatch(onDismiss: onDismiss) { [router] in
                router.push(.usdcDepositEducation)
            }
        }
        .buttonStyle(.filled)
    }
}
