//
//  AppContainer.swift
//  Code
//
//  Created by Dima Bart on 2022-08-11.
//

import SwiftUI
import CodeServices
import FlipchatServices
import CodeUI

@MainActor
class AppContainer: ObservableObject {
    
    let client = Client(
        network: Environment.current.network,
        context: Client.Context(kreIndex: KRE.index),
        queue: .main
    )
    
    let flipClient = FlipchatClient(network: .mainNet, queue: .main)
    
    let betaFlags = BetaFlags.shared
    let banners = Banners()
    let biometrics = Biometrics()
    let notificationController = NotificationController()
    
    let exchange: Exchange
    
    lazy private(set) var sessionAuthenticator = SessionAuthenticator(container: self)
    
    // MARK: - Init -
    
    init() {
        self.exchange = Exchange(client: client)
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
    
//    static func installationID() async throws -> String {
//        try await Installations.installations().installationID()
//    }
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
