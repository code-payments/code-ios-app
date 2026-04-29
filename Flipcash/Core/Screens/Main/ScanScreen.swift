//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ScanScreen: View {
    
    @Environment(SessionAuthenticator.self) private var sessionAuthenticator
    @Environment(Preferences.self) private var preferences
    @Environment(BetaFlags.self) private var betaFlags
    @Environment(AppRouter.self) private var router

    @Bindable private var session: Session

    @State private var viewModel: ScanViewModel

    @State private var giveViewModel: GiveViewModel

    @State private var cameraAuthorizer = CameraAuthorizer()

    @State private var sendButtonState: ButtonState = .normal
    @State private var sendButtonTask: Task<Void, Never>?

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
    
    var cameraAuthorized: Bool {
        cameraAuthorizer.status == .authorized
    }
    
    var directToSettingsForCamera: Bool? {
        switch cameraAuthorizer.status {
        case .authorized:
            return nil
        case .notDetermined:
            return false
        default:
            return true
        }
    }
    
    private let container: Container
    private let sessionContainer: SessionContainer
    
    // MARK: - Init -
    
    init(container: Container, sessionContainer: SessionContainer) {
        self.container        = container
        self.sessionContainer = sessionContainer
        self.session          = sessionContainer.session
        
        self.viewModel = ScanViewModel(
            container: container,
            sessionContainer: sessionContainer
        )

        self.giveViewModel = GiveViewModel(
            container: container,
            sessionContainer: sessionContainer
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        let showControls = session.billState.bill == nil
        ZStack {
            if cameraAuthorized {
                if preferences.cameraEnabled {
                    cameraViewport()
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeInOut(duration: 0.2).delay(0.3)),
                                removal: .identity
                            )
                        )
                }
            }
            
            billView()
            
            if showControls {
                // Any actionable views need to be positioned
                // in front of the BillCanvas, otherwise it
                // will swallow all touch events
                if !cameraAuthorized {
                    authorizeView()
                        .zIndex(1)
                        .transition(.opacity)
                    
                } else if !preferences.cameraEnabled {
                    manualCameraStart()
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
        }
        .background(Color.backgroundMain)
        .animation(.easeInOut(duration: 0.15), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: preferences.cameraEnabled)
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
        .sheet(item: Binding(
            get: { router.presentedSheet },
            set: { newValue in
                if newValue == nil {
                    router.dismissSheet()
                }
            }
        )) { sheet in
            RoutedSheet(
                sheet: sheet,
                container: container,
                sessionContainer: sessionContainer,
                giveViewModel: giveViewModel
            )
        }
        // Dismiss all presented sheets when a bill is about to appear.
        // Bills render in ScanScreen's ZStack, so any sheet on top
        // (Settings, Balance, Give) would obscure them. This ensures
        // cash links received via push notifications or deep links
        // are always visible regardless of the current navigation state.
        .onChange(of: session.presentationState.isPresenting) { _, isPresenting in
            guard isPresenting else { return }
            router.dismissSheet()
            giveViewModel.isPresented = false
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
            enableGestures: true,
            reverseZoom: false
        )
        .navigationBarHidden(true)
        .onAppear {
            viewModel.configureCameraSession()
        }
    }
    
    @ViewBuilder private func billView() -> some View {
        BillCanvas(
            state: session.presentationState,
            centerOffset: CGSize(width: 0, height: -30),
            preferredCanvasSize: preferredCanvasSize(),
            bill: session.billState.bill,
            action: nil,
            dismissHandler: dismissBill
        )
        .allowsHitTesting(session.presentationState.isPresenting)
        .edgesIgnoringSafeArea(.all)
    }
    
    private func preferredCanvasSize() -> CGSize {
        var rect = UIScreen.main.bounds
        
//        rect.size.height -= 54.0 // Top Bar
        rect.size.height -= 70.0 // Bottom bar
        
        return rect.insetBy(dx: 20, dy: 20).size
    }
    
    @ViewBuilder private func authorizeView() -> some View {
        let goToSettings = directToSettingsForCamera == true
        VStack(spacing: 40) {
            Text(goToSettings ? "You need to turn on Camera in Settings to scan Codes" : "Start your camera to grab cash")
                .frame(maxWidth: 260)
                .multilineTextAlignment(.center)
            
            BubbleButton(text: goToSettings ? "Open Settings" : "Start Camera") {
                if goToSettings {
                    URL.openSettings()
                } else {
                    Task {
                        try await cameraAuthorizer.authorize()
                    }
                }
            }
        }
        .padding(40)
        .font(.appTextSmall)
        .foregroundColor(.textMain)
    }
    
    @ViewBuilder private func manualCameraStart() -> some View {
        VStack(spacing: 40) {
            Text("You need to start your camera to grab cash")
                .frame(maxWidth: 240)
                .multilineTextAlignment(.center)
            
            BubbleButton(text: "Start Camera") {
                preferences.cameraEnabled.toggle()
            }
        }
        .padding(40)
        .font(.appTextSmall)
        .foregroundColor(.textMain)
        .onAppear {
            viewModel.stopCamera()
        }
    }
    
    @ViewBuilder private func interfaceView() -> some View {
        VStack {
            topBar()
            Spacer()
            bottomBar()
        }
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
    
    @ViewBuilder private func topBar() -> some View {
        HStack(alignment: .top) {
            Image.asset(.flipcashBrand)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 28)

            Spacer()

            GlassButton(asset: .hamburger, size: .regular) {
                router.present(.settings)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private func bottomBar() -> some View {
        HStack(alignment: .bottom) {
            LargeButton(
                title: "Give",
                image: .asset(.cash),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom
            ) {
                if giveViewModel.attemptPresent() {
                    router.present(.give)
                }
            }

            ToastContainer(toast: toast) {
                LargeButton(
                    title: "Wallet",
                    image: .asset(.history),
                    spacing: 12,
                    maxWidth: 80,
                    maxHeight: 80,
                    fullWidth: true,
                    aligment: .bottom
                ) {
                    router.present(.balance)
                }
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
    
    private func dismissBill() {
        session.dismissCashBill(style: .slide)
//        if let action = session.billState.secondaryAction {
//            action.action()
//        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String {
        self
    }
}

// MARK: - RoutedSheet -

/// Renders the modal sheet currently selected by `AppRouter.presentedSheet`.
/// Each case is a top-level modal; switching between them is a sheet swap.
private struct RoutedSheet: View {

    let sheet: AppRouter.SheetPresentation
    let container: Container
    let sessionContainer: SessionContainer
    let giveViewModel: GiveViewModel

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch sheet {
        case .balance:
            BalanceScreen(
                container: container,
                sessionContainer: sessionContainer
            )
        case .settings:
            SettingsScreen(
                container: container,
                sessionContainer: sessionContainer
            )
        case .give:
            // Stack bound to the router so deposit-mint pushes from inside
            // GiveScreen (`.currencyInfoForDeposit`) actually render.
            NavigationStack(path: $router[.give]) {
                GiveScreen(viewModel: giveViewModel)
                    .appRouterDestinations(container: container, sessionContainer: sessionContainer)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            ToolbarCloseButton {
                                giveViewModel.isPresented = false
                                router.dismissSheet()
                            }
                        }
                    }
            }
        }
    }
}

