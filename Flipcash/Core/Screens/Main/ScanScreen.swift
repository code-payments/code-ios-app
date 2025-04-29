//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-07.
//

import SwiftUI
import FlipcashUI

struct ScanScreen: View {
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    @StateObject private var viewModel: ScanViewModel
    
    @State private var cameraAuthorizer = CameraAuthorizer()
//    @State private var preferences = Preferences()
    
    @State private var isShowingBalance: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var isShowingGive: Bool = false
    
    private var toast: String? {
        if let toast = viewModel.toast {
            let formatted = toast.amount.formatted(suffix: nil)
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
    private let session: Session
    
    // MARK: - Init -
    
    init(container: Container, session: Session) {
        self.container = container
        self.session = session
        _viewModel = .init(wrappedValue: ScanViewModel(container: container, session: session))
    }
    
    // MARK: - Body -
    
    var body: some View {
        let showControls = viewModel.billState.bill == nil
        ZStack {
            if cameraAuthorized {
//                if preferences.cameraEnabled {
                    cameraViewport()
//                }
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
                    
                }
//                else if !preferences.cameraEnabled {
//                    manualCameraStart()
//                        .zIndex(1)
//                        .transition(.opacity)
//                }
            
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
        .ignoresSafeArea(.keyboard)
        .sheet(item: $viewModel.valuation) { valuation in
            PartialSheet(background: .backgroundMain, canAccessBackground: true) {
                ModalCashReceived(
                    title: "You received",
                    fiat: valuation.exchangedFiat.converted,
                    actionTitle: "Put in Wallet",
                    dismissAction: dismissBill
                )
            }
            .interactiveDismissDisabled()
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
            state: viewModel.presentationState,
            centerOffset: CGSize(width: 0, height: -30),
            preferredCanvasSize: preferredCanvasSize(),
            bill: viewModel.billState.bill,
            action: nil,
            dismissHandler: dismissBill
        )
        .allowsHitTesting(viewModel.presentationState.isPresenting)
        .edgesIgnoringSafeArea(.all)
//        .onChange(of: notificationController.willResignActive) { [weak session] _ in
//            session?.willResignActive()
//        }
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
            Text(goToSettings ? "You need to turn on Camera in Settings to scan Codes" : "Flipcash enables you to receive USDC by pointing your camera at the digital bill on another user's phone")
                .frame(maxWidth: 260)
                .multilineTextAlignment(.center)
            
            BubbleButton(text: goToSettings ? "Open Settings" : "Next") {
                if goToSettings {
                    URL.openSettings()
                } else {
                    cameraAuthorizer.authorize()
                }
            }
        }
        .padding(40)
        .font(.appTextSmall)
        .foregroundColor(.textMain)
    }
    
    @ViewBuilder private func manualCameraStart() -> some View {
        VStack(spacing: 40) {
            Text("You need to start your camera to scan Codes")
                .frame(maxWidth: 240)
                .multilineTextAlignment(.center)
            
            BubbleButton(text: "Start Camera") {
//                preferences.cameraEnabled.toggle()
            }
        }
        .padding(40)
        .font(.appTextSmall)
        .foregroundColor(.textMain)
        .onAppear {
//            cameraSession.stop()
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
            
            HStack(alignment: .center, spacing: 30) {
                if let primaryAction = viewModel.billState.primaryAction {
                    CapsuleButton(
                        state: .normal,
                        asset: primaryAction.asset,
                        title: primaryAction.title
                    ) {
                        Task {
                            try await primaryAction.action()
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder private func topBar() -> some View {
        HStack(alignment: .top) {
            Spacer()
            
            RoundButton(
                asset: .hamburger,
                size: .regular,
                binding: $isShowingSettings
            )
            .sheet(isPresented: $isShowingSettings) {
                SettingsScreen(
                    isPresented: $isShowingSettings,
                    container: container,
                    session: session
                )
//                .environmentObject(betaFlags)
//                .environmentObject(client)
//                .environmentObject(exchange)
//                .environmentObject(exchange)
//                .environmentObject(betaFlags)
//                .environmentObject(bannerController)
//                .environmentObject(biometrics)
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder private func bottomBar() -> some View {
        HStack(alignment: .bottom) {
            LargeButton(
                title: "Give",
                image: .asset(.tipcard),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                aligment: .bottom,
                binding: $isShowingGive
            )
            .sheet(isPresented: $isShowingGive) {
                GiveScreen(
                    isPresented: $isShowingGive,
                    scanViewModel: viewModel
                )
            }
            
            LargeButton(
                title: "Send",
                image: .asset(.airplane),
                spacing: 12,
                maxWidth: 80,
                maxHeight: 80,
                fullWidth: true,
                badgeInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 5),
                aligment: .bottom
            ) {
                
            }
            
            ToastContainer(toast: toast) {
                LargeButton(
                    title: "Balance",
                    image: .asset(.history),
                    spacing: 12,
                    maxWidth: 80,
                    maxHeight: 80,
                    fullWidth: true,
                    aligment: .bottom,
                    binding: $isShowingBalance
                )
            }
            .sheet(isPresented: $isShowingBalance) {
                BalanceScreen(isPresented: $isShowingBalance)
            }
        }
        .padding(.bottom, 10)
    }
    
    // MARK: - Actions -
    
    private func dismissBill() {
        viewModel.dismissCashBill(style: .slide)
//        if let action = session.billState.secondaryAction {
//            action.action()
//        }
    }
}
