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
    
    @EnvironmentObject private var sessionAuthenticator: SessionAuthenticator
    @EnvironmentObject private var statusController: StatusController
    
    @StateObject private var viewModel: ContainerViewModel
    
    // MARK: - Init -
    
    init(viewModel: @autoclosure @escaping () -> ContainerViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel())
    }
    
    // MARK: - Body -
    
    var body: some View {
        if statusController.requiresUpgrade {
            UpgradeScreen()
                .transition(.crossFade)
        } else {
            switch sessionAuthenticator.state {
            case .loggedIn(let sessionContainer):
                
                switch sessionAuthenticator.biometricState {
                case .disabled, .verified:
                    if sessionAuthenticator.isUnlocked {
                        RestrictedScreen(kind: .timelockAccountUnlocked)
                            .transition(.crossFade)
                        
                    } else {
                        ScanScreen(sessionContainer: sessionContainer)
                            .transition(.crossFade)
                    }
                    
                case .notVerified:
                    BiometricsAuthScreen(sessionAuthenticator: sessionAuthenticator)
                        .transition(.crossFade)
                }
                
            case .migrating:
                MigrationScreen()
                
            case .pending:
                SavedLoginScreen(
                    client: viewModel.container.client,
                    sessionAuthenticator: viewModel.container.sessionAuthenticator
                )
                .transition(.crossFade)
                
            case .loggedOut:
                IntroScreen(
                    viewModel: IntroViewModel(
                        container: viewModel.container
                    )
                )
                .transition(.crossFade)
            }
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

struct ContainerScreen_Previews: PreviewProvider {
    static var previews: some View {
        ContainerScreen(viewModel: ContainerViewModel(container: .mock))
            .environmentObjectsForSession()
    }
}
