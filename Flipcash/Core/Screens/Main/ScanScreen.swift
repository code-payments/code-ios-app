//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thin environment-reading wrapper that hands the DI containers to
/// ``ScanScreenContent``, whose `init` builds the `@State` scan view model and
/// `@Bindable` session synchronously. `ScanScreen` is the post-login root —
/// ``ContainerScreen`` injects the `SessionContainer` into the environment here.
struct ScanScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    /// When embedded as a tab in the v2 `HomeTabView`, the app-level
    /// `router.rootSheet` host is owned by the tab container instead, so this
    /// screen suppresses its own. Defaults to `false` — the v1 post-login root
    /// owns the host itself.
    var isEmbedded: Bool = false

    var body: some View {
        ScanScreenContent(container: container, sessionContainer: sessionContainer, isEmbedded: isEmbedded)
    }
}

private struct ScanScreenContent: View {

    @Environment(Preferences.self) private var preferences
    @Environment(AppRouter.self) private var router

    @Bindable private var session: Session

    @State private var viewModel: ScanViewModel

    @State private var cameraAuthorizer = CameraAuthorizer()

    private var toast: String? {
        if let toast = session.toast {
            let formatted = toast.amount.formatted()
            if toast.isDeposit {
                return "+\(formatted)"
            } else {
                return "-\(formatted)"
            }
        }
        return nil
    }
    
    private var cameraPrompt: CameraPrompt? {
        CameraPrompt(status: cameraAuthorizer.status, cameraEnabled: preferences.cameraEnabled)
    }
    
    private let sessionContainer: SessionContainer

    /// See ``ScanScreen/isEmbedded``.
    private let isEmbedded: Bool

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer, isEmbedded: Bool = false) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        self.isEmbedded       = isEmbedded

        self.viewModel = ScanViewModel(
            container: container,
            sessionContainer: sessionContainer
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        let showControls = session.billState.bill == nil
        ZStack {
            if cameraPrompt == nil {
                cameraViewport()
                    .transition(.identity)
            }
            
            if showControls {
                // Any actionable views need to be positioned
                // in front of the BillCanvas, otherwise it
                // will swallow all touch events
                if let cameraPrompt {
                    CameraPromptView(prompt: cameraPrompt, embedded: isEmbedded) {
                        performCameraPromptAction(cameraPrompt)
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }

                interfaceView()
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        // Fill the tab's full width and height. The iOS 26 native `TabView` does
        // not stretch tab content to fill, so without this the ZStack collapses to
        // its content width (the centered `CameraPromptView` at ~340pt, or the
        // camera viewport), leaving black bars down both sides of the scanner. The
        // v1 full-screen root masked this; only the embedded v2 tab exposed it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.15), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: preferences.cameraEnabled)
        .ignoresSafeArea(.keyboard)
        // The app-level `router.rootSheet` host (RoutedSheet + tip-resume + the
        // bill-dismiss hook). Owned here for the v1 root; when embedded as a v2
        // tab, `HomeTabView` owns it instead, so this suppresses its own to avoid
        // presenting the same sheet twice.
        //
        // The bill / tipcard surface itself (BillCanvas, actions, designer, and
        // the received-cash / send-tip sheets) is hoisted to `BillOverlayView` at
        // the app root — see `ContainerScreen` — so a pushed bill renders over any
        // tab, not only when this scanner is the mounted surface. `showControls`
        // still hides the scanner chrome while a bill is up.
        .modifier(RootSheetHostModifier(enabled: !isEmbedded))
        // Tells the app-root bill overlay the camera is behind it, so a grabbed
        // bill shows over the live camera without a scrim (v1, or the v2 Scan
        // tab). Any other surface gets the scrim.
        .onAppear { session.isScannerForeground = true }
        .onDisappear { session.isScannerForeground = false }
    }

    @ViewBuilder private func cameraViewport() -> some View {
        CameraViewport(
            session: viewModel.cameraSession,
            enableGestures: true
        )
        // Cross-fade the live preview in only once the first frame arrives, over
        // the dark placeholder — so the camera warm-up after a tab switch never
        // shows a black frame. See `ScanViewModel.isPreviewReady`.
        .opacity(viewModel.isPreviewReady ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isPreviewReady)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configureCameraSession()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
    
    private func performCameraPromptAction(_ prompt: CameraPrompt) {
        switch prompt {
        case .requestPermission:
            Task {
                try await cameraAuthorizer.authorize()
            }
        case .openSettings:
            URL.openSettings()
        case .startCamera:
            preferences.cameraEnabled.toggle()
        }
    }

    @ViewBuilder private func interfaceView() -> some View {
        VStack {
            // In the v2 tab-bar UI the scanner is a bare camera: the brand +
            // settings top bar and the v1 bottom navigation are replaced by the
            // app-level tab bar, so this chrome is suppressed when embedded.
            if !isEmbedded {
                ScanTopBar(
                    onBrand: { router.present(.downloadApp) },
                    onSettings: { router.present(.settings) }
                )
            }
            Spacer()
            if !isEmbedded {
                ScanBottomBar(
                    toast: toast,
                    showTips: session.canUseTips,
                    tipsBadgeCount: sessionContainer.conversationController.unreadConversationCount(of: .tipDm),
                    onGive: presentGive,
                    onWallet: { router.present(.balance) },
                    onDiscover: { router.present(.discover) },
                    onTips: { router.present(.tips) }
                )
            }
        }
        .opacity(session.isShowingBillDesigner ? 0 : 1)
    }

    // MARK: - Actions -

    private func presentGive() {
        let rate = sessionContainer.ratesController.rateForBalanceCurrency()
        if let dialog = giveCashGate(session: session, rate: rate).blockingDialog(router: router, addMoneySource: .scanner) {
            session.dialogItem = dialog
            return
        }
        router.present(.give)
    }
}


// MARK: - RoutedSheet -

/// Renders the modal sheet currently selected by `AppRouter.presentedSheet`.
/// Each case is a top-level modal; switching between them is a sheet swap.
private struct RoutedSheet: View {

    let sheet: AppRouter.SheetPresentation

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch sheet {
        case .balance:
            BalanceScreen()
        case .settings:
            SettingsScreen()
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
        case .discover:
            NavigationStack(path: $router[.discover]) {
                CurrencyDiscoveryScreen()
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
/// hook. Exactly one live view must own this so `router.present(_:)` works from
/// anywhere: the v1 root (`ScanScreen`) in the scanner-first UI, or the tab
/// container (`HomeTabView`) in the v2 UI. `enabled` lets `ScanScreen` suppress
/// its own copy when it is embedded as a v2 tab.
struct RootSheetHostModifier: ViewModifier {

    var enabled: Bool = true

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    private var session: Session { sessionContainer.session }

    func body(content: Content) -> some View {
        if enabled {
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
                // Bills render behind sheets, so any sheet on top (Settings,
                // Balance, Give) would obscure them. This ensures cash links
                // received via push notifications or deep links are always visible
                // regardless of the current navigation state.
                .onChange(of: session.presentationState.isPresenting) { _, isPresenting in
                    guard isPresenting else { return }
                    router.dismissSheet()
                }
        } else {
            content
        }
    }
}
