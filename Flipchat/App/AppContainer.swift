//
//  AppContainer.swift
//  Code
//
//  Created by Dima Bart on 2022-08-11.
//

import SwiftUI
import FlipchatServices
import Firebase

@MainActor
class AppContainer: ObservableObject {
    
    let client = Client(
        network: NetworkEnvironment.current.network,
        context: Client.Context(kreIndex: KRE.index),
        queue: .main
    )
    
    let flipClient = FlipchatClient(
        network: NetworkEnvironment.current.network,
        queue: .main
    )
    
    let banners = Banners()
    let betaFlags = BetaFlags.shared
    let biometrics = Biometrics()
    let notificationController = NotificationController()
    
    lazy private(set) var sessionAuthenticator = SessionAuthenticator(container: self)    
    
    lazy private(set) var exchange = Exchange(client: client)
    
    lazy private(set) var deepLinkController = DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    
    init() {
        let isRunningPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if !isRunningPreviews {
            FirebaseApp.configure()
        }
    }
    
//    private func registerPushNotifications() {
//        let push = pushController
//        if case .loggedIn = sessionAuthenticator.state {
//            if push.authorizationStatus == .notDetermined {
//                Task {
//                    try await push.authorize()
//                }
//            } else {
//                push.register()
//            }
//        } else {
//            push.register() // Logged out
//        }
//    }
    
    func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(self)
            .environmentObject(client)
            .environmentObject(flipClient)
        
            .environmentObject(betaFlags)
            .environmentObject(banners)
            .environmentObject(biometrics)
            .environmentObject(notificationController)

            .environmentObject(exchange)
            .environmentObject(sessionAuthenticator) 
    }
}

extension View {
    func injectingEnvironment(from container: AppContainer) -> some View {
        container.injectingEnvironment(into: self)
    }
}

// MARK: - Mark -

extension AppContainer {
    static var mock: AppContainer {
        AppContainer()
    }
}
