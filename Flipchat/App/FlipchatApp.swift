//
//  FlipchatApp.swift
//  Flipchat
//
//  Created by Dima Bart on 2024-09-24.
//

import SwiftUI
import CodeUI

@main
struct FlipchatApp: App {
    
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    @StateObject private var container = AppContainer()
    
    var body: some Scene {
        WindowGroup {
            ContainerScreen(sessionAuthenticator: container.sessionAuthenticator)
                .modelContainer(ChatStore.container)
                .injectingEnvironment(from: container)
        }
    }
}
