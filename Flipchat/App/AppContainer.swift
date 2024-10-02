//
//  AppContainer.swift
//  Code
//
//  Created by Dima Bart on 2022-08-11.
//

import SwiftUI
import CodeServices
import CodeUI

@MainActor
class AppContainer: ObservableObject {
    
    let client = Client(
        network: Environment.current.network,
        context: Client.Context(kreIndex: KRE.index),
        queue: .main
    )
    
    let betaFlags = BetaFlags.shared
    let bannerController = BannerController()
    let biometrics = Biometrics()
    
    let exchange: Exchange
    let sessionAuthenticator: SessionAuthenticator
    
    // MARK: - Init -
    
    init() {
        self.exchange = Exchange(client: client)
        self.sessionAuthenticator = SessionAuthenticator(
            client: client,
            exchange: exchange,
            bannerController: bannerController,
            betaFlags: betaFlags,
            biometrics: biometrics
        )
    }
    
    func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(self)
            .environmentObject(client)
        
            .environmentObject(betaFlags)
            .environmentObject(bannerController)
            .environmentObject(biometrics)

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
