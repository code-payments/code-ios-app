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
    
    @State private var tabSelection: TabBarItem = .flipchats
    
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
    
    private func resetTabBar() {
        tabSelection = .flipchats
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
        .onChange(of: sessionAuthenticator.state) { oldValue, newValue in
            if case .loggedOut = newValue {
                Task {
                    try await Task.delay(milliseconds: 250)
                    resetTabBar()
                }
            }
        }
    }
    
    @ViewBuilder private func homeView(state: AuthenticatedState) -> some View {
        NavigationStack(path: $viewModel.navigationPath) {
            TabBarView(selection: $tabSelection, isTabBarVisible: .constant(isTabBarVisible)) {
                ChatsScreen(
                    state: state,
                    container: container
                )
                .tabBarItem(
                    item: .flipchats,
                    selection: tabSelection
                )
                
                BalanceScreen(
                    session: state.session,
                    container: container
                )
                .tabBarItem(
                    item: .balance,
                    selection: tabSelection
                )
                
                ProfileScreen(
                    userID: state.session.userID,
                    isSelf: true,
                    state: state,
                    container: container
                )
                .tabBarItem(
                    item: .profile,
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
                            chatID: chatID,
                            state: authenticatedState,
                            container: container
                        )
                        
                    case .details(let chatID):
                        RoomDetailsScreen(
                            userID: authenticatedState.session.userID,
                            chatID: chatID,
                            state: authenticatedState,
                            container: container
                        )
                    }
                }
            }
        }
        .sheet(item: $viewModel.isShowingPreviewRoom) { preview in
            if let state = authenticatedState {
                PreviewRoomScreen(
                    chat: preview.chat,
                    members: preview.members,
                    host: preview.host,
                    viewModel: state.chatViewModel,
                    isModal: true
                )
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
