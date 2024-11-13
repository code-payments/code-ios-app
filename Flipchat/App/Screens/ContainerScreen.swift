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
    
    // MARK: - Init -
    
    init(sessionAuthenticator: SessionAuthenticator) {
        self.viewModel = sessionAuthenticator.containerViewModel
    }
    
    // MARK: - Body -
    
    var body: some View {
        Group {
            switch sessionAuthenticator.state {
            case .loggedIn(let state):
                
                switch sessionAuthenticator.biometricState {
                case .disabled, .verified:
                    if sessionAuthenticator.isUnlocked {
                        RestrictedScreen(kind: .timelockAccountUnlocked)
                    } else {
                        homeView(state: state)
                    }
                    
                case .notVerified:
                    BiometricsAuthScreen()
                }
                
            case .migrating:
                MigrationScreen()
                
            case .pending:
                SavedLoginScreen(
                    client: container.client,
                    sessionAuthenticator: sessionAuthenticator
                )
                
            case .loggedOut:
                IntroScreen(sessionAuthenticator: sessionAuthenticator)
            }
        }
        .transition(.crossFade)
    }
    
    @ViewBuilder private func homeView(state: AuthenticatedState) -> some View {
        NavigationStack(path: $viewModel.navigationPath) {
            TabBarView(selection: $tabSelection) {
                ChatsScreen(
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
                    title: "Kin",
                    asset: .kinHex,
                    selection: tabSelection
                )
            }
            .navigationDestination(for: ContainerPath.self) { path in
                switch path {
                case .chat(let chatID):
                    if let authenticatedState {
                        ConversationScreen(
                            userID: authenticatedState.session.userID,
                            chatID: chatID,
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

// MARK: - Previews -

#Preview {
    ContainerScreen(sessionAuthenticator: .mock)
        .environmentObjectsForSession()
}
