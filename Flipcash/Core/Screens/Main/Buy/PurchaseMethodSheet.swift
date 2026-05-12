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

                if session.hasCoinbaseOnramp {
                    ApplePayMethodButton(
                        context: context,
                        onDismiss: onDismiss
                    )
                }

                PhantomMethodButton(
                    context: context,
                    onDismiss: onDismiss,
                    router: router
                )

                OtherWalletMethodButton(
                    context: context,
                    onDismiss: onDismiss,
                    router: router
                )

                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.subtle)
            }
            .padding()
        }
    }
}

// Each row is its own struct so the body stays flat and avoids `@ViewBuilder`
// private functions (per CLAUDE.md's "no view functions" rule).

private struct ApplePayMethodButton: View {
    let context: PurchaseMethodContext
    let onDismiss: () -> Void

    var body: some View {
        Button {
            onDismiss()
            // TODO Task 10: wire up coordinator.startBuy(...) for the Apple
            // Pay verification + Coinbase order flow. For Task 6 the tap
            // just closes the picker so the rest of the visual flow can be
            // smoke-tested without a runtime crash.
        } label: {
            HStack(spacing: 4) {
                Text("Debit Card with")
                Text("\u{F8FF} Pay")
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
