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
    /// has one. Applied by the root sheet's content (`RoutedSheet`) and by
    /// every nested sheet's content (`NestedSheetRootView`), so the sheet
    /// stack renders at any depth — SwiftUI requires each nested sheet to be
    /// presented from within its parent sheet's content, not as siblings at
    /// the app root.
    ///
    /// The host hangs off a `background` sibling rather than wrapping the
    /// content: presentation preferences from the content
    /// (`interactiveDismissDisabled`, detents) must reach the content's own
    /// presentation without passing through a dormant `.sheet(item:)`, which
    /// swallows them (see `BuyReservesRegressionTests`).
    func appRouterNestedSheet() -> some View {
        modifier(AppRouterNestedSheetModifier())
    }
}

private struct AppRouterNestedSheetModifier: ViewModifier {

    @Environment(AppRouter.self) private var router
    @Environment(\.nestedSheetDepth) private var depth

    func body(content: Content) -> some View {
        // Each level binds to its own slot in `presentedSheets`. The setter
        // forwards user-driven dismissal (swipe-down) to `dismissSheet`, but
        // SwiftUI ALSO calls the setter with nil after a programmatic dismiss
        // completes. Without the in-bounds guard the setter would re-enter
        // `dismissSheet` and pop the parent sheet, cascading the dismissal.
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

/// Dispatches the active nested `SheetPresentation` to its root view. Lives
/// as a `View` (not a `@ViewBuilder` function) so SwiftUI tracks identity
/// per case — per CLAUDE.md "no view functions" rule.
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
                // Root-only sheets — they shouldn't be presented as nested. If
                // they ever are, we fall through to an empty view; the warning
                // in `presentNested` logs the mistake.
                EmptyView()
            }
        }
        // Each nested sheet hosts the level above it, mirroring the root
        // convention in `ScanScreen` — the recursion ends at the first
        // unoccupied `presentedSheets` slot.
        .appRouterNestedSheet()
    }
}

/// Root view for the `.buy(mint)` nested sheet. Owns the `NavigationStack`
/// bound to `router[.buy]`. `BuyAmountScreen` registers the
/// `.navigationDestination(for: BuyFlowPath.self)` modifier itself, so
/// sub-screens push naturally on this stack.
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
            // Sub-flow screens (Phantom, USDC deposit, processing) call
            // `dismissParentContainer` to close the whole `.buy` sheet on
            // success. BuyAmountScreen itself dismisses via the same env value
            // through its toolbar close button.
            .environment(\.dismissParentContainer, { router.dismissSheet() })
            // Top-level `AppRouter.Destination` cases (e.g. `.usdcDepositEducation`,
            // `.usdcDepositAddress`) are pushed from the Other Wallet path. They
            // share the same screens reached from the Wallet sheet, so register
            // the app-wide destination map here too.
            .appRouterDestinations()
            // Deposit-flow steps pushed inside the buy sheet after a method
            // selection from the Add Money options — the flow continues in
            // this sheet, and its close lands on the currency screen. See
            // `AddMoneyStartScreen.select(_:)`. The dismiss env is set here
            // directly: destination content doesn't inherit environment from
            // the root view's inner modifiers, only from its own attachment.
            .navigationDestination(for: AddMoneyFlowStep.self) { step in
                AddMoneyFlowDestination(step: step, onStep: { router.pushAny($0) })
                    .environment(\.dismissParentContainer, { router.dismissSheet() })
            }
        }
    }
}

/// Root view for the `.addMoney(context)` sheet: a content-sized
/// `AddMoneyStartScreen` prompt. Presented **nested** over a gating sheet
/// (buy/launch) and **at root** for the give-cash no-balance case (see
/// `RoutedSheet`). The deposit flow (amount entry → Adding Money) presents its
/// own full sheet on top from within that screen. Sub-screens call
/// `dismissParentContainer` to tear down the whole sheet on "OK".
struct AddMoneySheetRoot: View {

    let context: AddMoneyContext

    @Environment(AppRouter.self) private var router

    var body: some View {
        // Content-sized prompt (No Balance Yet → Select Method). `PartialSheet`
        // inside `AddMoneyStartScreen` drives the sheet to the content height;
        // the deposit flow (amount entry → Adding Money) presents its own full
        // sheet on top rather than pushing onto a stack.
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
