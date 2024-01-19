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
    
    @State private var sendState: ButtonState = .normal
    
    @State private var isPresentingFAQs: Bool = false
    @State private var isPresentingGetKin: Bool = false
    @State private var isPresentingHistory: Bool = false
    @State private var isPresentingGiveKin: Bool = false
    @State private var isPresentingBillExchange: Bool = false
    @State private var isPresentingSettings: Bool = false
    
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
//        .loading(
//            active: session.isReceivingRemoteSend,
//            text: "Collecting your cash",
//            color: .textMain
//        )
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
                    CodeBrand(size: .small, template: true)
                        .foregroundColor(.textMain)
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
                        title: Localized.Title.getKin,
                        image: .asset(.wallet),
                        maxWidth: 80,
                        maxHeight: 80,
                        aligment: .bottomLeading,
                        binding: $isPresentingGetKin
                    )
                    .sheet(isPresented: $isPresentingGetKin) {
//                        ContactsScreen(
//                            inviteController: inviteController,
//                            contactsController: contactsController,
//                            isPresented: $isPresentingInvites
//                        )
                        GetKinScreen(session: session, isPresented: $isPresentingGetKin)
                            .environmentObject(betaFlags)
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
                        
//                        LargeButton(
//                            title: Localized.Action.giveKin,
//                            image: .asset(.kinLarge),
//                            spacing: 8,
//                            maxWidth: 80,
//                            maxHeight: 80,
//                            aligment: .bottom,
//                            binding: $isPresentingGiveKin
//                        )
                        
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
                    }
                } else {
                    if !session.billState.hideBillButtons {
                        HStack(spacing: 0) {
                            if !betaFlags.hasEnabled(.giveRequests) {
                                CapsuleButton(
                                    state: sendState,
                                    asset: .send,
                                    title: Localized.Action.send
                                ) { [weak session] in
                                    sendState = .loading
                                    session?.sendRemotely {
                                        Task {
                                            try await Task.delay(seconds: 1)
                                            sendState = .normal
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            CapsuleButton(
                                state: .normal,
                                asset: .cancel,
                                title: Localized.Action.cancel
                            ) { [weak session] in
                                session?.cancelSend()
                            }
                            .frame(maxWidth: .infinity)
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
            dismissHandler: cancelSend
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
                amount: valuation.amount,
                dismissAction: { [weak session] in
                    session?.cancelSend()
                }
            )
            .zIndex(5)
            
        } else if let paymentConfirmation = session.billState.paymentConfirmation {
            if session.hasSufficientFunds(for: paymentConfirmation.requestedAmount) {
                ModalPaymentConfirmation(
                    amount: paymentConfirmation.localAmount,
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
                    subtitle: Localized.Subtitle.insufficientFundsDescription
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
                successAction: { [weak session] in
                    try await session?.completeLogin(
                        for: loginConfirmation.domain,
                        rendezvous: loginConfirmation.payload.rendezvous.publicKey
                    )
                    
                }, dismissAction: { [weak session] in
                    session?.cancelLogin()
                    
                }, cancelAction: { [weak session] in
                    session?.rejectLogin()
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
    
    private func cancelSend() {
        session.cancelSend()
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
                
//                LargeButton(
//                    title: Localized.Action.giveKin,
//                    image: .asset(.kinLarge),
//                    spacing: 8,
//                    maxWidth: 80,
//                    maxHeight: 80,
//                    aligment: .bottom,
//                    binding: .constant(false)
//                )
                
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
