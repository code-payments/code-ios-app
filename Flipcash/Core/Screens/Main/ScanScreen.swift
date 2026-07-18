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

    var body: some View {
        ScanScreenContent(container: container, sessionContainer: sessionContainer)
    }
}

private struct ScanScreenContent: View {

    @Environment(Preferences.self) private var preferences
    @Environment(AppRouter.self) private var router

    @Bindable private var session: Session

    @State private var viewModel: ScanViewModel

    @State private var cameraAuthorizer = CameraAuthorizer()

    @State private var sendButtonState: ButtonState = .normal
    @State private var sendButtonTask: Task<Void, Never>?
    @State private var billDesignerColors: [Color] = ColorEditorControl.randomDerivedColors()

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

    // MARK: - Init -

    init(container: Container, sessionContainer: SessionContainer) {
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session

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
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.2).delay(0.3)),
                            removal: .identity
                        )
                    )
            }
            
            billView()
            
            if showControls {
                // Any actionable views need to be positioned
                // in front of the BillCanvas, otherwise it
                // will swallow all touch events
                if let cameraPrompt {
                    CameraPromptView(prompt: cameraPrompt) {
                        performCameraPromptAction(cameraPrompt)
                    }
                    .zIndex(1)
                    .transition(.opacity)
                }
            
                interfaceView()
                    .zIndex(1)
                    .transition(.opacity)
            } else {
                billActions()
                    .zIndex(1)
                    .transition(.opacity)
            }

            if session.isShowingBillDesigner {
                BillDesignerOverlay(colors: $billDesignerColors)
                    .zIndex(2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.15), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: preferences.cameraEnabled)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: session.isShowingBillDesigner)
        .ignoresSafeArea(.keyboard)
        .sheet(item: $session.valuation) { valuation in
            PartialSheet(background: .clear, canAccessBackground: true) {
                ModalCashReceived(
                    title: "You received",
                    fiat: valuation.exchangedFiat.nativeAmount,
                    currencyName: valuation.mintMetadata?.name ?? "currency",
                    currencyImageURL: valuation.mintMetadata?.imageURL,
                    actionTitle: "Put in Wallet",
                    dismissAction: dismissBill
                )
            }
            .interactiveDismissDisabled()
        }
        // Swipe-to-dismiss writes nil through this binding; route through
        // `dismissSheet()` so the dismissal is logged. Programmatic presentations
        // go through `router.present(_:)` directly and never write through here.
        // Bound to `rootSheet` (bottom of the sheet stack) — nested sheets mount
        // inside this root sheet's content via `.appRouterNestedSheet`.
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
        // Bills render in ScanScreen's ZStack, so any sheet on top
        // (Settings, Balance, Give) would obscure them. This ensures
        // cash links received via push notifications or deep links
        // are always visible regardless of the current navigation state.
        .onChange(of: session.presentationState.isPresenting) { _, isPresenting in
            guard isPresenting else { return }
            router.dismissSheet()
        }
        // Reset button state on bill dismissal — `sendButtonState` outlives individual bills.
        .onChange(of: session.billState.bill) { _, newBill in
            guard newBill == nil else { return }
            sendButtonTask?.cancel()
            sendButtonTask = nil
            sendButtonState = .normal
        }
    }
    
    @ViewBuilder private func cameraViewport() -> some View {
        CameraViewport(
            session: viewModel.cameraSession,
            enableGestures: true
        )
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.configureCameraSession()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
    
    @ViewBuilder private func billView() -> some View {
        BillCanvas(
            state: session.presentationState,
            centerOffset: CGSize(width: 0, height: -30),
            preferredCanvasSize: preferredCanvasSize(),
            bill: session.billState.bill,
            dismissHandler: dismissBill
        )
        .allowsHitTesting(session.presentationState.isPresenting)
        .ignoresSafeArea()
    }

    private func preferredCanvasSize() -> CGSize {
        guard var rect = UIApplication.shared.firstWindowScene?.screen.bounds else {
            return .zero
        }

        rect.size.height -= 70.0 // Bottom bar

        return rect.insetBy(dx: 20, dy: 20).size
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
            ScanTopBar(
                onBrand: { router.present(.downloadApp) },
                onSettings: { router.present(.settings) }
            )
            Spacer()
            ScanBottomBar(
                toast: toast,
                showSend: session.canSend,
                sendBadgeCount: sessionContainer.conversationController.unreadConversationCount,
                onGive: presentGive,
                onWallet: { router.present(.balance) },
                onDiscover: { router.present(.discover) },
                onSend: { router.present(.send) }
            )
        }
        .opacity(session.isShowingBillDesigner ? 0 : 1)
    }
    
    @ViewBuilder private func billActions() -> some View {
        VStack {
            Spacer()
            
            GlassContainer(spacing: 30) {
                billActionButtons
            }
        }
        .padding(.bottom, 10)
    }
    
    private var billActionButtons: some View {
        HStack(alignment: .center, spacing: 30) {
            if let primaryAction = session.billState.primaryAction {
                CapsuleButton(
                    state: sendButtonState,
                    asset: primaryAction.asset,
                    title: primaryAction.title
                ) {
                    sendButtonTask?.cancel()
                    sendButtonTask = Task {
                        sendButtonState = .loading
                        do {
                            try await primaryAction.action()
                            try await Task.delay(milliseconds: 1000)
                        } catch {}
                        sendButtonState = .normal
                    }
                }
            }

            if let secondaryAction = session.billState.secondaryAction {
                CapsuleButton(
                    state: .normal,
                    asset: secondaryAction.asset,
                    title: secondaryAction.title
                ) {
                    secondaryAction.action()
                }
                .accessibilityLabel(secondaryAction.title ?? "Cancel")
            }
        }
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

    private func dismissBill() {
        session.dismissCashBill(style: .slide)
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
        case .addMoney(let context):
            // Add Money entered as a root sheet — the give-cash no-balance case
            // (Scan / deeplink). Buy & launch shortfalls present it *nested* over
            // their gating sheet via `presentNested(.addMoney(context))`.
            AddMoneySheetRoot(context: context)
        case .downloadApp:
            NavigationStack(path: $router[.downloadApp]) {
                DownloadAppScreen()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            CloseButton(action: router.dismissSheet)
                        }
                    }
            }
        case .send:
            SendRootScreen()
        case .sendAmount(let contact):
            // Send Cash entered directly as a root sheet — e.g. the notification
            // Send Cash deeplink / App Intent opens the amount entry with no chat
            // behind it. (In-chat Send Cash still enters it via presentNested.)
            SendAmountSheetRoot(contact: contact)
        }
    }
}
