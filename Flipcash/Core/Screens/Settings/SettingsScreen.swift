//
//  SettingsScreen.swift
//  Flipcash
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct SettingsScreen: View {
    @EnvironmentObject private var betaFlags: BetaFlags
    @EnvironmentObject private var preferences: Preferences
    
    @Binding public var isPresented: Bool
    
    @ObservedObject private var onrampViewModel: OnrampViewModel
    
    @State private var path: [SettingsPath] = []
    
    @State private var isShowingWithdrawFlow = false
    @State private var isShowingAccountSelection = false
    @State private var isShowingLogoutConfirmation = false
    @State private var isShowingAccessKey = false
    
    @State private var dialogItem: DialogItem?
    @State private var debugTapCount: Int = 0
    
    private let insets: EdgeInsets = EdgeInsets(
        top: 25,
        leading: 0,
        bottom: 25,
        trailing: 0
    )
    
    private let container: Container
    private let sessionAuthenticator: SessionAuthenticator
    private let sessionContainer: SessionContainer
    private let session: Session
    
    // MARK: - Init -
    
    public init(isPresented: Binding<Bool>, container: Container, sessionContainer: SessionContainer) {
        self._isPresented = isPresented
        self.container = container
        self.sessionAuthenticator = container.sessionAuthenticator
        self.sessionContainer = sessionContainer
        self.onrampViewModel = sessionContainer.onrampViewModel
        self.session = sessionContainer.session
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack(path: $path) {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 0) {

                    // Logo Header
                    logoHeader()
                        .padding(.top, -44)
                        .padding(.bottom, 30)
                    
                    // Content
                    ScrollBox(color: .backgroundMain) {
                        ScrollView(showsIndicators: false) {
                            list()
                        }
                    }
                    
                    // Footer
                    footer()
                }
                .padding(.top, 10)
                .padding(.bottom, 10)
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarCloseButton(binding: $isPresented)
                }
            }
            .navigationDestination(for: SettingsPath.self) { path in
                switch path {
                case .myAccount:
                    myAccountScreen()
                case .advancedFeatures:
                    advancedFeaturesScreen()
                case .depositUSDC:
                    DepositDescriptionScreen(
                        container: container,
                        sessionContainer: sessionContainer
                    )
                case .appSettings:
                    appSettingsScreen()
                case .betaFlagss:
                    BetaFlagsScreen(container: container)
                }
            }
            .sheet(isPresented: $onrampViewModel.isMethodSelectionPresented) {
                AddCashScreen(
                    isPresented: $onrampViewModel.isMethodSelectionPresented,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .sheet(isPresented: $onrampViewModel.isOnrampPresented) {
                PartialSheet(background: .backgroundMain) {
                    PresetAddCashScreen(
                        isPresented: $onrampViewModel.isOnrampPresented,
                        container: container,
                        sessionContainer: sessionContainer
                    )
                }
            }
            .sheet(isPresented: $isShowingWithdrawFlow) {
                WithdrawDescriptionScreen(
                    isPresented: $isShowingWithdrawFlow,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
        }
    }

    // MARK: - Header Components -

    @ViewBuilder private func logoHeader() -> some View {
        Button {
            handleLogoTap()
        } label: {
            Image.asset(.flipcashBrand)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 45)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lists -

    @ViewBuilder private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            
            navigationRow(
                path: $path,
                asset: .myAccount,
                title: "My Account",
                pathItem: .myAccount
            )
            
            navigationRow(
                path: $path,
                asset: .settings,
                title: "App Settings",
                pathItem: .appSettings
            )
            
            row(
                asset: .withdraw,
                title: "Withdraw Funds",
            ) {
                isShowingWithdrawFlow.toggle()
            }
            
            navigationRow(
                path: $path,
                asset: .sliders,
                title: "Advanced Features",
                pathItem: .advancedFeatures
            )
            
            if betaFlags.accessGranted {
                navigationRow(
                    path: $path,
                    asset: .debug,
                    title: "Beta Features",
                    badge: betaBadge(),
                    pathItem: .betaFlagss
                )
                
                row(asset: .switchAccounts, title: "Switch Accounts", badge: betaBadge()) {
                    isShowingAccountSelection.toggle()
                }
                .sheet(isPresented: $isShowingAccountSelection) {
                    AccountSelectionScreen(
                        isPresented: $isShowingAccountSelection,
                        sessionAuthenticator: sessionAuthenticator,
                        action: switchAccount
                    )
                }
            }
            
            row(asset: .logout, title: "Log Out") {
                dialogItem = .init(
                    style: .destructive,
                    title: "Are You Sure You Want To Log Out?",
                    subtitle: "You can get into this account using your Access Key",
                    dismissable: true
                ) {
                    DialogAction.destructive("Log Out") {
                        logout()
                    }
                    DialogAction.cancel {}
                }
            }
            
            Spacer()
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
        .dialog(item: $dialogItem)
        .dialog(item: $onrampViewModel.purchaseSuccess)
    }
    
    // MARK: - Advanced Features -
    
    @ViewBuilder private func advancedFeaturesScreen() -> some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    advancedFeaturesList()
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Advanced Features")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder private func advancedFeaturesList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            row(systemImage: "slider.horizontal.3", title: "Bill Creator") {
                isPresented = false
                Task {
                    try await Task.delay(milliseconds: 250)
                    session.isShowingBillEditor = true
                }
            }
            row(
                asset: .deposit,
                title: "Deposit Funds",
            ) {
                presentOnramp()
            }
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    // MARK: - My Account -
    
    @ViewBuilder private func myAccountScreen() -> some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    myAccountList()
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("My Account")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder private func myAccountList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            
            row(asset: .key, title: "Access Key") {
                dialogItem = .init(
                    style: .destructive,
                    title: "View Your Access Key?",
                    subtitle: "Your Access Key will grant access to your Flipcash account. Keep it private and safe",
                    dismissable: true
                ) {
                    DialogAction.destructive("View Access Key") {
                        isShowingAccessKey.toggle()
                    }
                    DialogAction.cancel {}
                }
            }
            .sheet(isPresented: $isShowingAccessKey) {
                NavigationStack {
                    AccessKeyBackupScreen(mnemonic: session.keyAccount.mnemonic)
                        .navigationTitle("Access Key")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                ToolbarCloseButton(binding: $isShowingAccessKey)
                            }
                        }
                }
            }
            
            row(asset: .delete, title: "Delete Account") {
                dialogItem = .init(
                    style: .destructive,
                    title: "Permanently Delete Account?",
                    subtitle: "This will permanently delete your Flipcash account",
                    dismissable: true
                ) {
                    DialogAction.destructive("Permanently Delete Account") {
                        logout()
                    }
                    DialogAction.cancel {}
                }
            }
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    // MARK: - App Settings -
    
    @ViewBuilder private func appSettingsScreen() -> some View {
        Background(color: .backgroundMain) {
            ScrollBox(color: .backgroundMain) {
                ScrollView(showsIndicators: false) {
                    appSettingsList()
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("App Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder private func appSettingsList() -> some View {
        VStack(alignment: .leading, spacing: 0) {
//            switch biometrics.kind {
//            case .none:
//                EmptyView()
//                
//            case .passcode:
//                toggle(
//                    image: .system(.faceID),
//                    title: Localized.Title.requirePasscode,
//                    isEnabled: biometricsEnabledBinding()
//                )
//                
//            case .faceID:
//                toggle(
//                    image: .system(.faceID),
//                    title: Localized.Title.requireFaceID,
//                    isEnabled: biometricsEnabledBinding()
//                )
//                
//            case .touchID:
//                toggle(
//                    image: .system(.touchID),
//                    title: Localized.Title.requireTouchID,
//                    isEnabled: biometricsEnabledBinding()
//                )
//            }
            
            toggle(
                image: .asset(.camera),
                title: "Auto Start Camera",
                isEnabled: cameraAutoStartDisabledBinding()
            )
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
    }
    
    private func cameraAutoStartDisabledBinding() -> Binding<Bool> {
        Binding(
            get: { !preferences.cameraAutoStartDisabled },
            set: { enabled in
                preferences.cameraAutoStartDisabled = !enabled
            }
        )
    }
    
    // MARK: - Utilities -
    
    @ViewBuilder private func navigationRow(path: Binding<[SettingsPath]>, asset: Asset, title: String, badge: Badge? = nil, pathItem: SettingsPath) -> some View {
        NavigationRow(path: path, insets: insets, pathItem: pathItem) {
            Image.asset(asset)
                .frame(minWidth: 45)
            Text(title)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
            Spacer()
            if let badge = badge {
                badge
            }
        }
    }
    
    @ViewBuilder private func row(asset: Asset, title: String, badge: Badge? = nil, action: @escaping VoidAction) -> some View {
        row(image: Image.asset(asset), title: title, badge: badge, action: action)
    }

    @ViewBuilder private func row(systemImage: String, title: String, badge: Badge? = nil, action: @escaping VoidAction) -> some View {
        row(image: Image(systemName: systemImage), title: title, badge: badge, action: action)
    }

    @ViewBuilder private func row(image: Image, title: String, badge: Badge? = nil, action: @escaping VoidAction) -> some View {
        Row(insets: insets) {
            image
                .frame(minWidth: 45)
            Text(title)
                .multilineTextAlignment(.leading)
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
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
                .padding(.trailing, 2)
                .tint(.textSuccess)
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
    
    private func betaBadge() -> Badge {
        Badge(decoration: .circle(.textWarning), text: "Beta")
    }
    
    // MARK: - Actions -

    private func handleLogoTap() {
        if debugTapCount >= 9 {
            // Toggle beta flags access
            betaFlags.setAccessGranted(!betaFlags.accessGranted)
            debugTapCount = 0
        } else {
            debugTapCount += 1
        }
    }

    private func presentOnramp() {
        onrampViewModel.presentRoot()
        Analytics.onrampOpenedFromSettings()
    }
    
    private func switchAccount(to account: AccountDescription) {
        Task {
            isPresented = false
            try await Task.delay(milliseconds: 250)
            
            sessionAuthenticator.switchAccount(to: account.account.mnemonic)
        }
    }
    
    private func logout() {
        Task {
            isPresented = false
            try await Task.delay(milliseconds: 250)
            
            sessionAuthenticator.logout()
        }
    }
}

// MARK: - Navigation -

extension SettingsScreen {
    enum SettingsPath {
        case myAccount
        case advancedFeatures
        case depositUSDC
        case appSettings
        case betaFlagss
    }
}
