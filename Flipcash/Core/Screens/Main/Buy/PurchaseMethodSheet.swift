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
            OtherWalletMethodButton(context: context, onDismiss: onDismiss, router: router)
        }
    }
}

private struct ApplePayMethodButton: View {
    let context: PurchaseMethodContext
    let onDismiss: () -> Void

    @Environment(OnrampCoordinator.self) private var coordinator

    var body: some View {
        Button {
            Analytics.buttonTapped(name: .buyWithCoinbase)
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: AppRouter.dismissAnimationDuration)
                coordinator.start(
                    .buy(mint: context.mint, displayName: context.currencyName),
                    amount: context.amount
                )
            }
        } label: {
            HStack(spacing: 4) {
                Text("Debit Card with")
                Text("\u{F8FF}Pay")
                    .font(.body.bold())
            }
        }
        .buttonStyle(.filled)
    }
}

private struct PhantomMethodButton: View {
    let context: PurchaseMethodContext
    let onDismiss: () -> Void
    let router: AppRouter

    var body: some View {
        Button {
            Analytics.buttonTapped(name: .buyWithPhantom)
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: AppRouter.dismissAnimationDuration)
                router.pushAny(BuyFlowPath.phantomEducation(mint: context.mint, amount: context.amount))
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
    let context: PurchaseMethodContext
    let onDismiss: () -> Void
    let router: AppRouter

    var body: some View {
        Button("Other Wallet") {
            onDismiss()
            Task { @MainActor in
                try? await Task.sleep(for: AppRouter.dismissAnimationDuration)
                router.pushAny(BuyFlowPath.usdcDepositEducation(mint: context.mint, amount: context.amount))
            }
        }
        .buttonStyle(.filled)
    }
}
