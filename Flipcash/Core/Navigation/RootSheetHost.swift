//
//  RootSheetHost.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore


/// Renders the modal sheet currently selected by `AppRouter.presentedSheet`.
/// Each case is a top-level modal; switching between them is a sheet swap.
private struct RoutedSheet: View {

    let sheet: AppRouter.SheetPresentation

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch sheet {
        case .give:
            NavigationStack(path: $router[.give]) {
                GiveScreen(mint: nil)
                .appRouterDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CloseButton(action: router.dismissSheet)
                    }
                }
            }
        case .buy:
            // `.buy` is a nested-only sheet — it should never be presented at
            // root. `presentNested(.buy(mint))` is the intended entry point.
            // Rendering EmptyView is a defensive no-op; the misuse is already
            // logged by the router when the stack is empty.
            EmptyView()
        case .addMoney:
            // Add Money entered as a root sheet — the give-cash no-balance case
            // (Scan / deeplink). Buy & launch shortfalls present it *nested* over
            // their gating sheet via `presentNested(.addMoney(context))`.
            AddMoneySheetRoot()
        case .downloadApp:
            NavigationStack(path: $router[.downloadApp]) {
                DownloadAppScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            CloseButton(action: router.dismissSheet)
                        }
                    }
            }
        case .tips:
            TipsSheetRoot()
        case .sendAmount(let target):
            // Send Cash entered directly as a root sheet — e.g. the notification
            // Send Cash deeplink / App Intent opens the amount entry with no chat
            // behind it. (In-chat Send Cash still enters it via presentNested.)
            SendAmountSheetRoot(target: target)
        }
    }
}

// MARK: - RootSheetHostModifier -

/// Hosts the app-level `router.rootSheet` presentation (the `RoutedSheet` swap),
/// the tip-resume-after-profile-creation hooks, and the dismiss-sheets-on-bill
/// hook. Owned by the tab container (`HomeTabView`) — exactly one live view must
/// own it so `router.present(_:)` works from anywhere.
///
/// The bill / tipcard surface itself (BillCanvas, actions, designer, and the
/// received-cash / send-tip sheets) lives in `BillOverlayView` at the app root —
/// see `ContainerScreen` — so a pushed bill renders over any tab.
struct RootSheetHostModifier: ViewModifier {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    private var session: Session { sessionContainer.session }

    func body(content: Content) -> some View {
        content
            // Resume a tip held for profile creation the moment the profile
            // becomes tippable. The sheet-close hook is the belt for a missed
            // flip edge (e.g. the profile record arriving mid-transition):
            // closing Tips with a held tip resumes it when a profile exists
            // and drops it when creation was abandoned.
            .onChange(of: session.profile?.isTippable ?? false) { _, isTippable in
                guard isTippable else { return }
                sessionContainer.tipFlow.resumeAfterProfileCreation()
            }
            .onChange(of: router.rootSheet) { old, new in
                guard old == .tips, new == nil else { return }
                if session.profile?.isTippable == true {
                    sessionContainer.tipFlow.resumeAfterProfileCreation()
                } else {
                    sessionContainer.tipFlow.abandonPendingTip()
                }
            }
            // Swipe-to-dismiss writes nil through this binding; route through
            // `dismissSheet()` so the dismissal is logged. Programmatic
            // presentations go through `router.present(_:)` directly and never
            // write through here. Bound to `rootSheet` (bottom of the sheet
            // stack) — nested sheets mount inside this root sheet's content
            // via `.appRouterNestedSheet`.
            .sheet(item: Binding(
                get: { router.rootSheet },
                set: { newValue in
                    if newValue == nil {
                        router.dismissSheet()
                    }
                }
            )) { sheet in
                RoutedSheet(sheet: sheet)
                    .appRouterNestedSheet()
            }
            // Dismiss all presented sheets when a bill is about to appear.
            // Bills render behind sheets, so any sheet on top (Give, Tips)
            // would obscure them. This ensures cash links received via
            // push notifications or deep links are always visible regardless of
            // the current navigation state.
            .onChange(of: session.presentationState.isPresenting) { _, isPresenting in
                guard isPresenting else { return }
                router.dismissSheet()
            }
    }
}
