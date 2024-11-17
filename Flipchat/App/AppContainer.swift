//
//  AppContainer.swift
//  Code
//
//  Created by Dima Bart on 2022-08-11.
//

import SwiftUI
import FlipchatServices

@MainActor
class AppContainer: ObservableObject {
    
    let client = Client(
        network: Environment.current.network,
        context: Client.Context(kreIndex: KRE.index),
        queue: .main
    )
    
    let flipClient = FlipchatClient(network: .mainNet, queue: .main)
    
    let betaFlags = BetaFlags.shared
    let biometrics = Biometrics()
    let notificationController = NotificationController()
    
    lazy private(set) var sessionAuthenticator = SessionAuthenticator(container: self)
    
    lazy private(set) var pushController = PushController(
        sessionAuthenticator: sessionAuthenticator,
        client: flipClient
    )
    
    lazy private(set) var banners = Banners()
    
    lazy private(set) var exchange = Exchange(client: client)
    
    init() {
        // Register for remote notifications
        pushController.register()
    }
    
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
