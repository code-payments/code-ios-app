//
//  FlipchatApp.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-09-24.
//

import SwiftUI
import CodeUI
import Firebase

@main
struct FlipchatApp: App {
    
    @SwiftUI.Environment(\.scenePhase) private var scenePhase
    
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContainerScreen(sessionAuthenticator: delegate.container.sessionAuthenticator)
                .injectingEnvironment(from: delegate.container)
                .colorScheme(.dark)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        delegate.sceneDidBecomeActive()
                    case .inactive:
                        break
                    case .background:
                        delegate.sceneDidEnterBackground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
