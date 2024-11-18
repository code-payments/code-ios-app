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
    
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContainerScreen(sessionAuthenticator: delegate.container.sessionAuthenticator)
                .modelContainer(ChatStore.container)
                .injectingEnvironment(from: delegate.container)
                .colorScheme(.dark)
        }
    }
}
