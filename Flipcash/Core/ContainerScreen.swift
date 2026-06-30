//
//  ContainerScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-16.
//

import SwiftUI
import FlipcashUI

struct ContainerScreen: View {

    @Environment(SessionAuthenticator.self) var sessionAuthenticator

    var body: some View {
        VStack {
            if sessionAuthenticator.requiresUpgrade {
                ForceUpgradeScreen()
                    .transition(.opacity)
            } else if sessionAuthenticator.requiresForceLogout {
                ForceLogoutScreen()
                    .transition(.opacity)
            } else {
                switch sessionAuthenticator.state {
                case .loggedOut:
                    IntroScreen()
                        .transition(.opacity)

                case .migrating, .pending:
                    VStack {
                        LoadingView(color: .white)
                    }
                    .transition(.opacity)

                case .loggedIn(let sessionContainer):
                    ScanScreen()
                        .modifier(OnrampHostModifier())
                        .injectingEnvironment(from: sessionContainer)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: sessionAuthenticator.state.intValue)
        .animation(.easeOut(duration: 0.3), value: sessionAuthenticator.requiresUpgrade)
        .animation(.easeOut(duration: 0.3), value: sessionAuthenticator.requiresForceLogout)
    }
}
