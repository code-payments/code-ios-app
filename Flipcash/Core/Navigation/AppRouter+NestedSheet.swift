//
//  AppRouter+NestedSheet.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-05-12.
//

import SwiftUI
import FlipcashCore

extension View {

    /// Mounts the nested sheet (one level deeper than this view's depth) when
    /// `AppRouter.presentedSheets` has one. Apply on every sheet's content
    /// view tree so a nested sheet at that depth can render — SwiftUI requires
    /// nested sheets to be presented from within the parent sheet's content,
    /// not as siblings at the app root.
    ///
    /// Supports one level of nesting; depth-3+ would need a presentedSheets-
    /// aware conditional mount. A previous recursive version mounted a dormant
    /// inner `.sheet(item:)` that swallowed `interactiveDismissDisabled` from
    /// descendants, re-enabling swipe-dismiss on screens that opted out.
    func appRouterNestedSheet(container: Container, sessionContainer: SessionContainer) -> some View {
        modifier(AppRouterNestedSheetModifier(container: container, sessionContainer: sessionContainer))
    }
}

private struct AppRouterNestedSheetModifier: ViewModifier {

    let container: Container
    let sessionContainer: SessionContainer

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
        return content.sheet(item: binding) { nested in
            NestedSheetRootView(
                sheet: nested,
                container: container,
                sessionContainer: sessionContainer
            )
            .environment(\.nestedSheetDepth, depth + 1)
        }
    }
}

/// Dispatches the active nested `SheetPresentation` to its root view. Lives
/// as a `View` (not a `@ViewBuilder` function) so SwiftUI tracks identity
/// per case — per CLAUDE.md "no view functions" rule.
private struct NestedSheetRootView: View {

    let sheet: AppRouter.SheetPresentation
    let container: Container
    let sessionContainer: SessionContainer

    var body: some View {
        switch sheet {
        case .buy(let mint):
            BuySheetRoot(
                mint: mint,
                container: container,
                sessionContainer: sessionContainer
            )

        case .balance, .settings, .give, .discover:
            // Root-only sheets — they shouldn't be presented as nested. If
            // they ever are, we fall through to an empty view; the warning
            // in `presentNested` logs the mistake.
            EmptyView()
        }
    }
}

/// Root view for the `.buy(mint)` nested sheet. Owns the `NavigationStack`
/// bound to `router[.buy]`. `BuyAmountScreen` registers the
/// `.navigationDestination(for: BuyFlowPath.self)` modifier itself, so
/// sub-screens push naturally on this stack.
private struct BuySheetRoot: View {

    let mint: PublicKey
    let container: Container
    let sessionContainer: SessionContainer

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
        }
    }
}
