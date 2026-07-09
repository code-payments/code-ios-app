//
//  AppRouter+NestedSheet.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

extension View {

    /// Mounts the next-deeper nested sheet when `AppRouter.presentedSheets`
    /// has one. SwiftUI only stacks sheets presented from within the parent
    /// sheet's content, and a wrapping `.sheet(item:)` would swallow the
    /// content's `interactiveDismissDisabled` — hence the `background` host
    /// (see `BuyReservesRegressionTests`).
    func appRouterNestedSheet() -> some View {
        modifier(AppRouterNestedSheetModifier())
    }
}

private struct AppRouterNestedSheetModifier: ViewModifier {

    @Environment(AppRouter.self) private var router
    @Environment(\.nestedSheetDepth) private var depth

    func body(content: Content) -> some View {
        // SwiftUI also calls the setter with nil after a programmatic dismiss
        // completes; without the in-bounds guard that re-entry would pop the
        // parent sheet too.
        let myDepth = depth + 1
        let binding = Binding<AppRouter.SheetPresentation?>(
            get: {
                guard router.presentedSheets.indices.contains(myDepth) else { return nil }
                return router.presentedSheets[myDepth]
            },
            set: { newValue in
                guard newValue == nil else { return }
                guard router.presentedSheets.indices.contains(myDepth) else { return }
                router.dismissSheet()
            }
        )
        return content.background(
            Color.clear.sheet(item: binding) { nested in
                NestedSheetRootView(sheet: nested)
                    .environment(\.nestedSheetDepth, myDepth)
            }
        )
    }
}

/// Dispatches the active nested `SheetPresentation` to its root view.
private struct NestedSheetRootView: View {

    let sheet: AppRouter.SheetPresentation

    var body: some View {
        Group {
            switch sheet {
            case .buy(let mint):
                BuySheetRoot(mint: mint)

            case .sendAmount(let contact):
                SendAmountSheetRoot(contact: contact)

            case .addMoney(let context):
                AddMoneySheetRoot(context: context)

            case .balance, .settings, .give, .discover, .downloadApp, .send:
                // Root-only sheets; `presentNested` logs a warning if one
                // lands here.
                EmptyView()
            }
        }
        // Hosts the next level; the recursion ends at the first unoccupied
        // `presentedSheets` slot.
        .appRouterNestedSheet()
    }
}

/// Root view for the `.buy(mint)` nested sheet — owns the `NavigationStack`
/// bound to `router[.buy]`.
private struct BuySheetRoot: View {

    let mint: PublicKey

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router[.buy]) {
            BuyAmountScreen(
                mint: mint,
                currencyName: sessionContainer.session.balance(for: mint)?.name ?? "this currency",
                session: sessionContainer.session,
                ratesController: sessionContainer.ratesController
            )
            .id(mint)
            .environment(\.dismissParentContainer, { router.dismissSheet() })
            .appRouterDestinations()
            // The dismiss env must be set at the registration: destination
            // content doesn't inherit environment from the root view's inner
            // modifiers.
            .navigationDestination(for: AddMoneyFlowStep.self) { step in
                AddMoneyFlowDestination(step: step, onStep: { router.pushAny($0) })
                    .environment(\.dismissParentContainer, { router.dismissSheet() })
            }
        }
    }
}

/// Root view for the `.addMoney(context)` sheet — the content-sized
/// `AddMoneyStartScreen` prompt.
struct AddMoneySheetRoot: View {

    let context: AddMoneyContext

    @Environment(AppRouter.self) private var router

    var body: some View {
        AddMoneyStartScreen(context: context)
            .environment(\.dismissParentContainer, { router.dismissSheet() })
    }
}

/// Root view for the `.sendAmount(contact)` sheet — Send Cash, presented either stacked on the
/// chat (in-chat send) or directly as a root sheet (notification deeplink / App Intent). The
/// `NavigationStack` is unbound: nothing pushes onto it, so it exists only to render the toolbar.
struct SendAmountSheetRoot: View {

    let contact: ResolvedContact

    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            SendAmountScreen(contact: contact)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton(action: router.dismissSheet)
                    }
                }
        }
    }
}
