//
//  ContainerScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-02-19.
//

import SwiftUI
import CodeUI
import CodeServices

struct ContainerScreen: View {
    
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        switch sessionAuthenticator.state {
        case .loggedIn(let sessionContainer):
            
            switch sessionAuthenticator.biometricState {
            case .disabled, .verified:
                if sessionAuthenticator.isUnlocked {
                    RestrictedScreen(kind: .timelockAccountUnlocked)
                        .transition(.crossFade)
                    
                } else {
                    ContentView()
                        .transition(.crossFade)
                }
                
            case .notVerified:
                BiometricsAuthScreen()
                    .transition(.crossFade)
            }
            
        case .migrating:
            MigrationScreen()
            
        case .pending:
            SavedLoginScreen(
                client: container.client,
                sessionAuthenticator: sessionAuthenticator
            )
            .transition(.crossFade)
            
        case .loggedOut:
            IntroScreen()
                .transition(.crossFade)
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

// MARK: - ViewModel -

@MainActor
class ContainerViewModel: ObservableObject {
    
    let container: AppContainer
    
    // MARK: - Init -
    
    init(container: AppContainer) {
        self.container = container
    }
}

// MARK: - Previews -

#Preview {
    ContainerScreen()
        .environmentObjectsForSession()
}
