//
//  SettingsScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import CodeUI
import CodeServices
import SwiftUIIntrospect

struct SettingsScreen: View {
    
    @Binding public var isPresented: Bool
    
    @ObservedObject private var session: Session

    @EnvironmentObject private var client: Client
    @EnvironmentObject private var exchange: Exchange
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var bannerController: BannerController
    @EnvironmentObject private var biometrics: Biometrics
    @EnvironmentObject private var preferences: Preferences
    
    @State private var isPresentingAccountSelection = false
    @State private var isPresentingRecoveryPhrase = false
    @State private var isPresentingBuyKin = false
    @State private var debugTapCount: Int = 0
    
    private let insets: EdgeInsets = EdgeInsets(
        top: 25,
        leading: 0,
        bottom: 25,
        trailing: 0
    )
    
    private var isPhoneLinked: Bool {
        session.phoneLink?.isLinked == true
    }
    
    // MARK: - Init -
    
    public init(session: Session, isPresented: Binding<Bool>) {
        self.session = session
        self._isPresented = isPresented
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationView {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 0) {
                    
                    // Header
                    ZStack {
                        GeometryReader { proxy in
                            HStack {
                                Spacer()
                                
                                CodeBrand(size: .medium)
                                    .onTapGesture {
                                        if debugTapCount > 9 {
                                            if betaFlags.accessGranted {
                                                betaFlags.setAccessGranted(false)
                                            } else {
                                                if session.user.betaFlagsAllowed {
                                                    betaFlags.setAccessGranted(true)
                                                }
                                            }
                                            
                                            debugTapCount = 0
                                        } else {
                                            debugTapCount += 1
                                        }
                                    }
                                
                                Spacer()
                            }
                            .padding(.vertical, 20)
                            
                            Button {
                                isPresented.toggle()
                            } label: {
                                Image.asset(.close)
                                    .padding(20)
                            }
                            .frame(width: 60, height: 60)
                            .position(x: proxy.size.width - 20, y: proxy.size.height - 57)
                        }
                    }
                    .frame(height: 100)
                    
                    // Content
                    ScrollBox(color: .backgroundMain) {
                        ScrollView(showsIndicators: false) {
                            list()
                        }
                        .introspect(.scrollView, on: .iOS(.v15, .v16, .v17)) {
                            $0.alwaysBounceVertical = false
                        }
                    }
                    
                    // Footer
                    footer()
                }
                .padding(.top, 10)
                .padding(.bottom, 10)
                .padding(.horizontal, 20)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            Analytics.open(screen: .settings)
            ErrorReporting.breadcrumb(.settingsScreen)
            validateBetaFlagAccess()
        }
    }
    
    // MARK: - App Settings -
    
    @ViewBuilder private func appSettingsScreen() -> some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    appSettingsList()
                }
                .introspect(.scrollView, on: .iOS(.v15, .v16, .v17)) {
                    $0.alwaysBounceVertical = false
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitle(Text(Localized.Title.appSettings), displayMode: .inline)
    }
    
    @ViewBuilder private func appSettingsList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch biometrics.kind {
            case .none:
                EmptyView()
                
            case .passcode:
                toggle(
                    image: .system(.faceID),
                    title: Localized.Title.requirePasscode,
                    isEnabled: biometricsEnabledBinding()
                )
                
            case .faceID:
                toggle(
                    image: .system(.faceID),
                    title: Localized.Title.requireFaceID,
                    isEnabled: biometricsEnabledBinding()
                )
                
            case .touchID:
                toggle(
                    image: .system(.touchID),
                    title: Localized.Title.requireTouchID,
                    isEnabled: biometricsEnabledBinding()
                )
            }
            
            toggle(
                image: .asset(.camera),
                title: Localized.Title.autoStartCamera,
                isEnabled: cameraAutoStartDisabledBinding()
            )
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    // MARK: - My Account -
    
    @ViewBuilder private func accountScreen() -> some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    accountList()
                }
                .introspect(.scrollView, on: .iOS(.v15, .v16, .v17)) {
                    $0.alwaysBounceVertical = false
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationBarTitle(Text(Localized.Title.myAccount), displayMode: .inline)
    }
    
    @ViewBuilder private func accountList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(isActive: $isPresentingRecoveryPhrase) {
                LazyView(
                    BackupScreen(
                        mnemonic: session.organizer.mnemonic,
                        owner: session.organizer.ownerKeyPair.publicKey
                    )
                )
            } label: {
                EmptyView()
            }
            
            row(asset: .key, title: Localized.Title.accessKey) {
                bannerController.show(
                    style: .error,
                    title: Localized.Prompt.Title.viewAccessKey,
                    description: Localized.Prompt.Description.viewAccessKey,
                    position: .bottom,
                    actionStyle: .stacked,
                    actions: [
                        .destructive(title: Localized.Action.viewAccessKey) {
                            Task {
                                await showAccessKey()
                            }
                        },
                        .cancel(title: Localized.Action.cancel),
                    ]
                )
            }
            
            navigationRow(
                asset: .phone,
                title: Localized.Title.phoneNumber,
                badge: linkedBadge()
            ) {
                LinkPhoneScreen(session: session)
            }
            
            navigationRow(asset: .delete, title: Localized.Action.deleteAccount) {
                DeleteAccountScreen(
                    viewModel:
                        DeleteAccountViewModel(
                            sessionAuthenticator: sessionAuthenticator,
                            bannerController: bannerController
                        )
                )
            }
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    // MARK: - Settings -
    
    @ViewBuilder private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(asset: .dollar, title: Localized.Action.buyMoreKin) {
                isPresentingBuyKin.toggle()
            }
            .sheet(isPresented: $isPresentingBuyKin) {
                BuyKinScreen(
                    isPresented: $isPresentingBuyKin,
                    viewModel: BuyKinViewModel(
                        session: session,
                        client: client,
                        exchange: exchange,
                        bannerController: bannerController,
                        betaFlags: betaFlags
                    )
                )
            }
            
            navigationRow(asset: .deposit, title: Localized.Title.depositKin) {
                LazyView(
                    DepositScreen(session: session)
                )
            }
            
            navigationRow(asset: .withdraw, title: Localized.Title.withdrawKin) {
                LazyView(
                    WithdrawAmountScreen(viewModel: withdrawViewModel())
                )
            }
            
            navigationRow(asset: .myAccount, title: Localized.Title.myAccount) {
                accountScreen()
            }
            
            navigationRow(asset: .settings, title: Localized.Title.appSettings) {
                appSettingsScreen()
            }
            
            navigationRow(asset: .faq, title: Localized.Title.faq) {
                FAQScreen(isPresented: nil)
            }
            
            if betaFlags.accessGranted {
                row(asset: .switchAccounts, title: Localized.Title.switchAccounts, badge: betaBadge()) {
                    isPresentingAccountSelection.toggle()
                }
                .sheet(isPresented: $isPresentingAccountSelection) {
                    AccountSelectionScreen(
                        isPresented: $isPresentingAccountSelection,
                        sessionAuthenticator: sessionAuthenticator,
                        action: switchAccount
                    )
                    .environmentObject(client)
                    .environmentObject(exchange)
                }
                    
                navigationRow(asset: .debug, title: Localized.Title.betaFlags, badge: betaBadge()) {
                    BetaFlagsScreen(
                        betaFlags: betaFlags,
                        tipController: session.tipController
                    )
                }
            }
            
            row(asset: .logout, title: Localized.Action.logout) {
                bannerController.show(
                    style: .error,
                    title: Localized.Prompt.Title.logout,
                    description: Localized.Prompt.Description.logout,
                    position: .bottom,
                    actionStyle: .stacked,
                    actions: [
                        .destructive(title: Localized.Action.logout, action: logout),
                        .cancel(title: Localized.Action.cancel),
                    ]
                )
            }
            
            Spacer()
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    // MARK: - Utilities -
    
    @ViewBuilder private func navigationRow<D>(asset: Asset, title: String, badge: Badge? = nil, @ViewBuilder destination: @escaping () -> D) -> some View where D: View {
        NavigationRow(insets: insets, destination: destination) {
            Image.asset(asset)
                .frame(minWidth: 45)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let badge = badge {
                badge
            }
        }
    }
    
    @ViewBuilder private func row(asset: Asset, title: String, badge: Badge? = nil, action: @escaping VoidAction) -> some View {
        Row(insets: insets) {
            Image.asset(asset)
                .frame(minWidth: 45)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let badge = badge {
                badge
            }
        } action: {
            action()
        }
    }
    
    @ViewBuilder private func toggle(image: Image, title: String, isEnabled: Binding<Bool>) -> some View {
        Row(insets: insets) {
            image
                .frame(minWidth: 45)
            Toggle(title, isOn: isEnabled)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.trailing, 2)
        }
    }
    
    @ViewBuilder private func footer() -> some View {
        VStack {
            Text("Version \(AppMeta.version) • Build \(AppMeta.build)")
                .lineLimit(1)
                .font(.appTextHeading)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth:. infinity)
    }
    
    private func linkedBadge() -> Badge {
        Badge(
            decoration: isPhoneLinked ? .checkmark : .none,
            text: isPhoneLinked ? Localized.Title.linked : Localized.Title.notLinked
        )
    }
    
    private func betaBadge() -> Badge {
        Badge(decoration: .circle(.textWarning), text: "Beta")
    }
    
    private func biometricsEnabledBinding() -> Binding<Bool> {
        Binding(
            get: { biometrics.isEnabled },
            set: { enabled in
                Task {
                    let enabled = await biometrics.setEnabledAndVerify(enabled)
                    Analytics.requireBiometrics(enabled: enabled)
                }
            }
        )
    }
    
    private func cameraAutoStartDisabledBinding() -> Binding<Bool> {
        Binding(
            get: { !preferences.cameraAutoStartDisabled },
            set: { enabled in
                preferences.cameraAutoStartDisabled = !enabled
                Analytics.cameraAutoStart(enabled: enabled)
            }
        )
    }
    
    // MARK: - Validation -
    
    private func validateBetaFlagAccess() {
        if !session.user.betaFlagsAllowed {
            // Turn off beta flags for any users
            // that have beta flags disallowed
            betaFlags.setAccessGranted(false)
        }
    }
    
    // MARK: - Withdraw -
    
    private func withdrawViewModel() -> WithdrawViewModel {
        WithdrawViewModel(session: session, exchange: exchange, biometrics: biometrics) { success in
            if success {
                isPresented = false
            }
        }
    }
    
    // MARK: - Actions -
    
    private func showAccessKey() async {
//        if let context = biometrics.verificationContext() {
//            guard await context.verify(reason: .access) else {
//                return
//            }
//        }
        isPresentingRecoveryPhrase = true
    }
    
    private func switchAccount(to account: AccountDescription) {
        isPresentingAccountSelection = false
        logout()
        Task {
            try await Task.delay(seconds: 1)
            sessionAuthenticator.completeLogin(with: try await sessionAuthenticator.initialize(using: account.account.mnemonic))
        }
    }
    
    private func logout() {
        Analytics.logout()
        sessionAuthenticator.logout()
    }
}

// MARK: - Item -

extension SettingsScreen {
    struct Item {
        
        let title: String
        let action: VoidAction
        
        init(title: String, action: @escaping VoidAction) {
            self.title = title
            self.action = action
        }
    }
}

// MARK: - Previews -

struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        SettingsScreen(session: .mock, isPresented: .constant(true))
            .environmentObjectsForSession()
            .environmentObject(BetaFlags.shared)
    }
}
