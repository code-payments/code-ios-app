//
//  ContainerScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-16.
//

import SwiftUI
import FlipcashUI

struct ContainerScreen: View {
    
    @EnvironmentObject var sessionAuthenticator: SessionAuthenticator
    
    private let container: Container
    
    init(container: Container) {
        self.container = container
    }
    
    var body: some View {
        VStack {
            switch sessionAuthenticator.state {
            case .loggedOut:
                IntroScreen(container: container)
                    .transition(.opacity)
                
            case .migrating, .pending:
                VStack {
                    LoadingView(color: .white)
                }
                .transition(.opacity)
                
            case .loggedIn(let sessionContainer):
                ScanScreen(
                    container: container,
                    sessionContainer: sessionContainer
                )
                .environmentObject(sessionContainer.session)
                .environmentObject(sessionContainer.historyController)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: sessionAuthenticator.state.intValue)
    }
}
