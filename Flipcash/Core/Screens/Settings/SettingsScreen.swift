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
    
    @Binding public var isPresented: Bool
    
    @State private var isShowingWithdrawFlow = false
    @State private var isShowingAccountSelection = false
    @State private var isShowingLogoutConfirmation = false
    
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
        self.session = sessionContainer.session
    }
    
    // MARK: - Body -
    
    var body: some View {
        NavigationStack {
            Background(color: .backgroundMain) {
                VStack(alignment: .center, spacing: 0) {
                    
                    // Header
                    ZStack {
                        GeometryReader { proxy in
                            HStack {
                                Spacer()
                                Image.asset(.flipcashBrand)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 40)
                                    .onTapGesture {
                                        if debugTapCount > 9 {
                                            if betaFlags.accessGranted {
                                                betaFlags.setAccessGranted(false)
                                            } else {
//                                                if session.user.betaFlagsAllowed {
                                                betaFlags.setAccessGranted(true)
//                                                }
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
    }
    
    @ViewBuilder private func list() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if betaFlags.accessGranted {
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
            
            navigationRow(asset: .deposit, title: "Deposit") {
                DepositScreen(session: session)
            }
            
            row(asset: .withdraw, title: "Withdraw") {
                isShowingWithdrawFlow.toggle()
            }
            .sheet(isPresented: $isShowingWithdrawFlow) {
                WithdrawAmountScreen(
                    isPresented: $isShowingWithdrawFlow,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            
            row(asset: .logout, title: "Log Out") {
                dialogItem = .init(
                    style: .destructive,
                    title: "Are you sure you want to log out?",
                    subtitle: "You can get into this account using your Access Key",
                    dismissable: true
                ) {
                    DialogAction.destructive("Log Out") {
                        logout()
                    }
                    DialogAction.cancel {}
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
            
            Spacer()
        }
        .font(.appDisplayXS)
        .foregroundColor(.textMain)
        .dialog(item: $dialogItem)
    }
    
    // MARK: - Utilities -
    
    @ViewBuilder private func navigationRow<D>(asset: Asset, title: String, badge: Badge? = nil, @ViewBuilder destination: @escaping () -> D) -> some View where D: View {
        NavigationRow(insets: insets, destination: destination) {
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
        Row(insets: insets) {
            Image.asset(asset)
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
    
    private func switchAccount(to account: AccountDescription) {
        Task {
            isPresented = false
            try await Task.delay(milliseconds: 250)
            
            sessionAuthenticator.switchAccount(to: account)
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
