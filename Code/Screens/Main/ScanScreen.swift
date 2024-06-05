//
//  ScanScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-01-19.
//

import SwiftUI
import CodeServices
import CodeUI
import AVKit

struct ScanScreen: View {
    
    @ObservedObject private var session: Session
    @ObservedObject private var inviteController: InviteController
    @ObservedObject private var historyController: HistoryController
    @ObservedObject private var contactsController: ContactsController
    
    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var cameraSession: CameraSession<CodeExtractor>
    @EnvironmentObject private var cameraAuthorizer: CameraAuthorizer
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var notificationController: NotificationController
    @EnvironmentObject private var reachability: Reachability
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var biometrics: Biometrics
    
    @State private var sendState: ButtonState = .normal
    
    @State private var isPresentingFAQs: Bool = false
    @State private var isPresentingGetKin: Bool = false
    @State private var isPresentingHistory: Bool = false
    @State private var isPresentingGiveKin: Bool = false
    @State private var isPresentingBillExchange: Bool = false
    @State private var isPresentingSettings: Bool = false
    @State private var isPresentingDownload: Bool = false
    
    private var overrideAuthorization: AVAuthorizationStatus?
    
    private var directToSettings: Bool? {
        switch overrideAuthorization ?? cameraAuthorizer.status {
        case .authorized:
            return nil
        case .notDetermined:
            return false
        default:
            return true
        }
    }
    
    private var cameraAuthorized: Bool {
        cameraAuthorizer.status == .authorized
    }
    
    // MARK: - Init -
    
    init(sessionContainer: SessionContainer) {
        self.session = sessionContainer.session
        self.inviteController = sessionContainer.inviteController
        self.historyController = sessionContainer.historyController
        self.contactsController = sessionContainer.contactsController
    }
    
    fileprivate init(sessionContainer: SessionContainer, overrideAuthorization: AVAuthorizationStatus) {
        self.session = sessionContainer.session
        self.inviteController = sessionContainer.inviteController
        self.historyController = sessionContainer.historyController
        self.overrideAuthorization = overrideAuthorization
        self.contactsController = sessionContainer.contactsController
    }
    
    // MARK: - Body -
    
    var body: some View {
        let isInterfaceVisible = session.billState.bill == nil
        ZStack {
            if cameraAuthorized {
                cameraPreviewView()
            }
            billView()
            if !cameraAuthorized {
                authorizeView(isVisible: isInterfaceVisible)
            }
            interfaceView(isVisible: isInterfaceVisible)
            modalView()
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $session.showTipEntry) {
            session.cancelTipAmountEntry()
        } content: {
            EnterTipScreen(
                isPresented: $session.showTipEntry,
                viewModel: EnterTipViewModel(
                    session: session,
                    client: client,
                    exchange: exchange,
                    bannerController: bannerController,
                    betaFlags: betaFlags
                )
            )
        }
    }
    
    @ViewBuilder private func authorizeView(isVisible: Bool) -> some View {
        if let directToSettings = directToSettings {
            VStack(spacing: 40) {
                if isVisible {
                    Group {
                        Text(directToSettings ? Localized.Subtitle.allowCameraSettings : Localized.Subtitle.allowCameraAccess)
                            .multilineTextAlignment(.center)
                        Button {
                            if directToSettings {
                                URL.openSettings()
                            } else {
                                cameraAuthorizer.authorize()
                            }
                        } label: {
                            TextBubble(
                                style: .filled,
                                text: directToSettings ? Localized.Action.openSettings : Localized.Action.next,
                                paddingVertical: 5,
                                paddingHorizontal: 15
                            )
                        }
                    }
                    .transition(fadeTransition())
                }
            }
            .padding(40)
            .font(.appTextSmall)
            .foregroundColor(.textMain)
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder private func cameraPreviewView() -> some View {
        CameraPreviewView(session: cameraSession)
            .background(Color.backgroundMain)
            .edgesIgnoringSafeArea(.all)
            .navigationBarHidden(true)
            .onAppear {
                do {
                    try cameraSession.configureDevices()
                    cameraSession.start()
                } catch {
                    trace(.failure, components: "Error configuring camera session: \(error)")
                }
            }
    }
    
    @ViewBuilder private func interfaceView(isVisible: Bool) -> some View {
        VStack {
            topBar(isVisible: isVisible)
            Spacer()
            bottomBar(isVisible: isVisible)
        }
    }
    
    @ViewBuilder private func topBar(isVisible: Bool) -> some View {
        HStack {
            Group {
                if isVisible {
                    Button {
                        isPresentingDownload.toggle()
                    } label: {
                        CodeBrand(size: .small, template: true)
                            .foregroundColor(.textMain)
                    }
                    .tooltip(properties: .default, text: "Tap the logo to share the app download link")
                    .sheet(isPresented: $isPresentingDownload) {
                        DownloadScreen(isPresented: $isPresentingDownload)
                    }
                    
                    Spacer()
                    
                    RoundButton(
                        asset: .hamburger,
                        size: .regular,
                        binding: $isPresentingSettings
                    )
                    .sheet(isPresented: $isPresentingSettings) { [unowned session] in
                        SettingsScreen(
                            session: session,
                            isPresented: $isPresentingSettings
                        )
                        .environmentObject(betaFlags)
                        .environmentObject(client)
                        .environmentObject(exchange)
                        .environmentObject(exchange)
                        .environmentObject(betaFlags)
                        .environmentObject(bannerController)
                        .environmentObject(biometrics)
                    }
                }
            }
            .transition(fadeTransition())
        }
        .padding([.trailing, .leading], 20)
    }
    
    @ViewBuilder private func bottomBar(isVisible: Bool) -> some View {
        HStack(alignment: .bottom) {
            Group {
                if isVisible {
                    LargeButton(
                        title: betaFlags.hasEnabled(.giveRequests) ? Localized.Title.requestKin : Localized.Title.getKin,
                        image: .asset(.wallet),
                        maxWidth: 80,
                        maxHeight: 80,
                        aligment: .bottomLeading,
                        binding: $isPresentingGetKin
                    )
                    .sheet(isPresented: $isPresentingGetKin) {
                        if betaFlags.hasEnabled(.giveRequests) {
                            RequestKinScreen(
                                session: session,
                                isPresented: $isPresentingGetKin
                            )
                            .environmentObject(bannerController)
                            .environmentObject(exchange)
                            .environmentObject(reachability)
                        } else {
                            GetKinScreen(
                                session: session,
                                isPresented: $isPresentingGetKin
                            )
                            .environmentObject(betaFlags)
                            .environmentObject(client)
                            .environmentObject(exchange)
                            .environmentObject(bannerController)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 5) {
                        if betaFlags.hasEnabled(.showConnectivityStatus) && reachability.status == .offline {
                            HStack {
                                Image(systemName: "wifi.slash")
                                Text("No Connection")
                            }
                            .padding([.top, .bottom], 6)
                            .padding([.leading, .trailing], 8)
                            .font(.appTextHeading)
                            .foregroundColor(.textMain)
                            .background(
                                RoundedRectangle(cornerRadius: 99)
                                    .fill(Color.bannerError)
                            )
                        }
                        
                        LargeButton(
                            title: Localized.Action.giveKin,
                            content: {
                                Hex()
                                    .frame(width: 54, height: 60, alignment: .center)
                            },
                            spacing: 8,
                            maxWidth: 80,
                            maxHeight: 80,
                            aligment: .bottom,
                            binding: $isPresentingGiveKin
                        )
                    }
                    
                    Spacer()
                    
                    ToastContainer(toast: toast()) {
                        LargeButton(
                            title: Localized.Action.balance,
                            image: .asset(.history),
                            maxWidth: 80,
                            maxHeight: 80,
                            aligment: .bottomTrailing,
                            binding: $isPresentingHistory
                        )
                        .if(historyController.unreadCount > 0) { $0
                            .badged(historyController.unreadCount, insets: .init(
                                top: 22,
                                leading: 0,
                                bottom: 0,
                                trailing: 8
                            ))
                        }
                    }
                    .sheet(isPresented: $isPresentingHistory) { [unowned session] in
                        BalanceScreen(
                            session: session,
                            historyController: historyController,
                            isPresented: $isPresentingHistory
                        )
                        .environmentObject(exchange)
                        .environmentObject(client)
                        .environmentObject(betaFlags)
                        .environmentObject(bannerController)
                        .environmentObject(notificationController)
                    }
                } else {
                    if !session.billState.hideBillButtons {
                        HStack(spacing: 0) {
                            if let primaryAction = session.billState.primaryAction {
                                CapsuleButton(
                                    state: sendState,
                                    asset: primaryAction.asset,
                                    title: primaryAction.title
                                ) {
                                    Task {
                                        sendState = .loading
                                        try await primaryAction.action()
                                        if let delay = primaryAction.loadingStateDelayMillisenconds {
                                            try await Task.delay(milliseconds: delay)
                                        }
                                        sendState = .normal
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            if let secondaryAction = session.billState.secondaryAction {
                                CapsuleButton(
                                    state: .normal,
                                    asset: secondaryAction.asset,
                                    title: secondaryAction.title
                                ) {
                                    secondaryAction.action()
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                }
            }
            .transition(fadeTransition())
        }
        .padding([.trailing, .leading], isVisible ? 30 : 0)
        .padding(.bottom, 10)
        .sheet(isPresented: $isPresentingGiveKin) { [unowned session] in
            GiveKinScreen(session: session, isPresented: $isPresentingGiveKin)
                .environmentObject(exchange)
        }
    }
    
    @ViewBuilder private func billView() -> some View {
        BillCanvas(
            state: session.presentationState,
            centerOffset: CGSize(width: 0, height: -30),
            preferredCanvasSize: preferredCanvasSize(),
            bill: session.billState.bill,
            action: billAction,
            dismissHandler: dismissBill
        )
        .edgesIgnoringSafeArea(.all)
        .onChange(of: notificationController.willResignActive) { [weak session] _ in
            session?.willResignActive()
        }
    }
    
    @ViewBuilder private func modalView() -> some View {
        if let valuation = session.billState.valuation {
            ModalCashReceived(
                title: valuation.title,
                amount: valuation.amount.kin.formattedFiat(rate: valuation.amount.rate, showOfKin: true),
                currency: valuation.amount.rate.currency,
                secondaryAction: Localized.Action.putInWallet,
                dismissAction: { [weak session] in
                    session?.cancelSend()
                }
            )
            .zIndex(5)
            
        } else if let paymentConfirmation = session.billState.paymentConfirmation {
            if session.hasSufficientFunds(for: paymentConfirmation.requestedAmount) {
                ModalPaymentConfirmation(
                    amount: paymentConfirmation.localAmount.kin.formattedFiat(rate: paymentConfirmation.localAmount.rate, showOfKin: true),
                    currency: paymentConfirmation.localAmount.rate.currency,
                    primaryAction: Localized.Action.swipeToPay,
                    secondaryAction: Localized.Action.cancel,
                    paymentAction: { [weak session] in
                        try await session?.completePayment(
                            for: paymentConfirmation.requestedAmount,
                            rendezvous: paymentConfirmation.payload.rendezvous
                        )
                        
                    }, dismissAction: { [weak session] in
                        session?.cancelPayment(rejected: false)
                        
                    }, cancelAction: { [weak session] in
                        session?.rejectPayment()
                    }
                )
                .zIndex(5)
                
            } else {
                ModalInsufficientFunds(
                    title: Localized.Title.insufficientFunds,
                    subtitle: Localized.Subtitle.insufficientFundsDescription,
                    primaryAction: Localized.Title.getMoreKin,
                    secondaryAction: Localized.Action.cancel
                ) { [weak session] in
                    Task {
                        session?.rejectPayment(ignoreRedirect: true)
                        try await Task.delay(milliseconds: 400)
                        isPresentingGetKin.toggle()
                    }
                    
                } dismissAction: { [weak session] in
                    session?.rejectPayment()
                }
                .zIndex(5)
            }
            
        } else if let loginConfirmation = session.billState.loginConfirmation {
            ModalLoginConfirmation(
                domain: loginConfirmation.domain,
                primaryAction: Localized.Action.swipeToLogin,
                secondaryAction: Localized.Action.cancel,
                successAction: { [weak session] in
                    try await session?.completeLogin(
                        for: loginConfirmation.domain,
                        rendezvous: loginConfirmation.payload.rendezvous.publicKey
                    )
                    
                }, dismissAction: { [weak session] in
                    session?.cancelLogin(rejected: false)
                    
                }, cancelAction: { [weak session] in
                    session?.rejectLogin()
                }
            )
            .zIndex(5)
            
        } else if let tipConfirmation = session.billState.tipConfirmation {
            ModalTipConfirmation(
                username: tipConfirmation.username,
                amount: tipConfirmation.amount.kin.formattedFiat(rate: tipConfirmation.amount.rate, showOfKin: true),
                currency: tipConfirmation.amount.rate.currency,
                avatar: tipConfirmation.avatar,
                user: tipConfirmation.user,
                primaryAction: Localized.Action.swipeToTip,
                secondaryAction: Localized.Action.cancel,
                paymentAction: { [weak session] in
                    try await session?.completeTipPayment(amount: tipConfirmation.amount)
                },
                dismissAction: { [weak session] in
                    session?.cancelTip()
                },
                cancelAction: { [weak session] in
                    session?.cancelTip()
                }
            )
            .zIndex(5)
        }
    }
    
    private func preferredCanvasSize() -> CGSize {
        var rect = UIScreen.main.bounds
        
//        rect.size.height -= 54.0 // Top Bar
        rect.size.height -= 70.0 // Bottom bar
        
        return rect.insetBy(dx: 20, dy: 20).size
    }
    
    private func billAction() {
        isPresentingBillExchange.toggle()
    }
    
    private func dismissBill() {
        if let action = session.billState.secondaryAction {
            action.action()
        }
    }
    
    // MARK: - Transitions -
    
    private func fadeTransition() -> AnyTransition {
        .opacity
        .animation(
            .easeInOut
            .speed(2.5)
        )
    }
    
    // MARK: - Utilities -
    
    private func toast() -> String? {
        if let toast = session.billState.toast {
            let formatted = toast.amount.kin.formattedFiat(
                rate: toast.amount.rate,
                showOfKin: true
            )
            
            if toast.isDeposit {
                return "+\(formatted)"
            } else {
                return "-\(formatted)"
            }
        }
        return nil
    }
}

// MARK: - Placeholder -

extension ScanScreen {
    struct Placeholder: View {
        
        var body: some View {
            Background(color: .backgroundMain) {
                VStack {
                    topBar()
                    Spacer()
                    bottomBar()
                }
            }
        }
        
        @ViewBuilder private func topBar() -> some View {
            HStack {
                Image.asset(.codeBrand)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 100)
                    .foregroundColor(.textMain)
                Spacer()
                RoundButton(
                    asset: .hamburger,
                    size: .regular,
                    binding: .constant(false)
                )
            }
            .padding([.trailing, .leading], 20)
        }
        
        @ViewBuilder private func bottomBar() -> some View {
            HStack(alignment: .bottom) {
                LargeButton(
                    title: Localized.Title.getKin,
                    image: .asset(.wallet),
                    maxWidth: 80,
                    maxHeight: 80,
                    aligment: .bottomLeading,
                    binding: .constant(false)
                )
                
                Spacer()
                
                LargeButton(
                    title: Localized.Action.giveKin,
                    content: {
                        Hex()
                            .frame(width: 54, height: 60, alignment: .center)
                    },
                    spacing: 8,
                    maxWidth: 80,
                    maxHeight: 80,
                    aligment: .bottom,
                    binding: .constant(false)
                )
                
                Spacer()
                
                LargeButton(
                    title: Localized.Action.balance,
                    image: .asset(.history),
                    maxWidth: 80,
                    maxHeight: 80,
                    aligment: .bottomTrailing,
                    binding: .constant(false)
                )
            }
            .padding([.trailing, .leading], 30)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Tooltip Properties -

extension Tooltip.Properties {
    static let `default` = Tooltip.Properties(
        arrowSize: CGSize(
            width: 12,
            height: 6
        ),
        cornerRadius: 10,
        maxWidth: 200,
        distance: 8,
        backgroundColor: .backgroundMain.opacity(0.9),
        textPadding: CGSize(width: 13, height: 11),
        textFont: .appTextMessage,
        textAlignment: .leading,
        textColor: .textMain
    )
}

// MARK: - Previews -

struct ScanScreen_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ScanScreen.Placeholder()
            ScanScreen(sessionContainer: .mock, overrideAuthorization: .authorized)
            ScanScreen(sessionContainer: .mock, overrideAuthorization: .notDetermined)
            ScanScreen(sessionContainer: .mock, overrideAuthorization: .denied)
        }
        .environmentObjectsForSession()
    }
}
