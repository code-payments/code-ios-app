//
//  ContainerScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-02-19.
//

import SwiftUI
import CodeUI
import FlipchatServices

struct ContainerScreen: View {
    
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    @State private var tabSelection: TabBarItem = .init(title: "Chats", asset: .bubble)
    
    @ObservedObject private var viewModel: ContainerViewModel
    
    private var authenticatedState: AuthenticatedState? {
        if case .loggedIn(let state) = sessionAuthenticator.state {
            return state
        }
        return nil
    }
    
    private var isTabBarVisible: Bool {
        if case .loggedIn(let state) = sessionAuthenticator.state {
            return state.session.isRegistered
        }
        return false
    }
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.viewModel = sessionAuthenticator.containerViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack {
            switch sessionAuthenticator.state {
            case .loggedIn(let state):
                
                switch sessionAuthenticator.biometricState {
                case .disabled, .verified:
                    if sessionAuthenticator.isUnlocked {
                        RestrictedScreen(kind: .timelockAccountUnlocked)
                            .transition(.opacity)
                    } else {
                        homeView(state: state)
                            .transition(.opacity)
                    }
                    
                case .notVerified:
                    BiometricsAuthScreen()
                        .transition(.opacity)
                }
                
            case .migrating:
                MigrationScreen()
                    .transition(.opacity)
                
            case .pending:
                SavedLoginScreen(
                    client: container.client,
                    sessionAuthenticator: sessionAuthenticator
                )
                .transition(.opacity)
                
            case .loggedOut:
                IntroScreen(
                    sessionAuthenticator: sessionAuthenticator,
                    banners: container.banners
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: sessionAuthenticator.state.intValue)
    }
    
    @ViewBuilder private func homeView(state: AuthenticatedState) -> some View {
            NavigationStack(path: $viewModel.navigationPath) {
                TabBarView(selection: $tabSelection, isTabBarVisible: .constant(isTabBarVisible)) {
                    ChatsScreen(
                        sessionAuthenticator: sessionAuthenticator,
                        session: state.session,
                        chatController: state.chatController,
                        viewModel: state.chatViewModel
                    )
                    .tabBarItem(
                        title: "Chats",
                        asset: .bubble,
                        selection: tabSelection
                    )
                    
                    BalanceScreen(
                        session: state.session,
                        container: container
                    )
                    .tabBarItem(
                        title: "Balance",
                        asset: .kinHex,
                        selection: tabSelection
                    )
                }
                .navigationBarHidden(true)
                .navigationBarTitle("", displayMode: .inline)
                .navigationDestination(for: ContainerPath.self) { path in
                    if let authenticatedState {
                        switch path {
                        case .chat(let chatID):
                            ConversationScreen(
                                userID: authenticatedState.session.userID,
                                chatID: chatID,
                                session: state.session,
                                containerViewModel: state.containerViewModel,
                                chatViewModel: state.chatViewModel,
                                chatController: authenticatedState.chatController
                            )
                            
                        case .details(let chatID):
                            RoomDetailsScreen(
                                kind: .leaveRoom,
                                chatID: chatID,
                                viewModel: state.chatViewModel,
                                chatController: authenticatedState.chatController
                            )
                        }
                    }
                }
            }
    }
}

struct BlackScreen: View {
    var body: some View {
        Background(color: .black) {
            VStack{}
        }
    }
}

extension SessionAuthenticator.AuthenticationState {
    var intValue: Int {
        switch self {
        case .loggedOut: return 0
        case .migrating: return 1
        case .pending:   return 2
        case .loggedIn:  return 3
        }
    }
}

// MARK: - Previews -

#Preview {
    ContainerScreen(sessionAuthenticator: .mock)
        .environmentObjectsForSession()
}
