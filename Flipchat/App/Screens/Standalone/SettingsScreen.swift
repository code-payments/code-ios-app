//
//  SettingsScreen.swift
//  Flipchat
//
//  Created by Dima Bart on 2021-03-02.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct SettingsScreen: View {
    
    @Binding public var isPresented: Bool

    @EnvironmentObject private var banners: Banners
//    @EnvironmentObject private var client: Client
//    @EnvironmentObject private var exchange: Exchange
//    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
//    @EnvironmentObject private var betaFlags: BetaFlags
//    @EnvironmentObject private var biometrics: Biometrics
    
    @State private var isPresentingAccountSelection = false
    
    private let insets: EdgeInsets = EdgeInsets(
        top: 25,
        leading: 0,
        bottom: 25,
        trailing: 0
    )
    
    private let sessionAuthenticator: SessionAuthenticator
    private let session: Session
    
    // MARK: - Init -
    
    public init(sessionAuthenticator: SessionAuthenticator, session: Session, isPresented: Binding<Bool>) {
        self.sessionAuthenticator = sessionAuthenticator
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
                                Image(with: .brandLarge)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 90)
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
            row(asset: .switchAccounts, title: Localized.Title.switchAccounts, badge: betaBadge()) {
                isPresentingAccountSelection.toggle()
            }
            .sheet(isPresented: $isPresentingAccountSelection) {
                AccountSelectionScreen(
                    isPresented: $isPresentingAccountSelection,
                    sessionAuthenticator: sessionAuthenticator,
                    action: switchAccount
                )
            }
                
//            navigationRow(asset: .debug, title: Localized.Title.betaFlags, badge: betaBadge()) {
//                BetaFlagsScreen(
//                    betaFlags: betaFlags,
//                    tipController: session.tipController
//                )
//            }
            
            
            row(asset: .logout, title: "Log Out") {
                banners.show(
                    style: .error,
                    title: "Log out?",
                    description: "Are you sure you want to log out?",
                    position: .bottom,
                    actions: [
                        .destructive(title: "Log Out", action: logout),
                        .cancel(title: "Cancel"),
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
            
            logout()
            try await Task.delay(seconds: 1)
            
            sessionAuthenticator.completeLogin(
                with: try await sessionAuthenticator.initialize(
                    using: account.account.mnemonic,
                    name: nil,
                    isRegistration: false
                )
            )
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

#Preview {
    SettingsScreen(
        sessionAuthenticator: .mock,
        session: .mock,
        isPresented: .constant(true)
    )
}
