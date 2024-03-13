//
//  AppContainer.swift
//  Code
//
//  Created by Dima Bart on 2022-08-11.
//

import Foundation
import SwiftUI
import CodeServices
import CodeUI
import Firebase
import FirebaseInstallations

@MainActor
class AppContainer {
    
    let client = Client(
        network: Environment.current.network,
        context: Client.Context(kreIndex: KRE.index),
        queue: .main
//        DispatchQueue(
//            label: "com.code.client.queue",
//            qos: .utility,
//            attributes: .concurrent,
//            autoreleaseFrequency: .workItem
//        )
    )
    
    let cameraSession = CameraSession<CodeExtractor>()
    let cameraAuthorizer = CameraAuthorizer()
    let betaFlags = BetaFlags.shared
    let notificationController = NotificationController()
    let statusController = StatusController()
    let bannerController = BannerController()
    let reachability = Reachability()
    let biometrics = Biometrics()
    
    let abacus: Abacus
    let exchange: Exchange
    let contentController: ContentController
    let pushController: PushController
    let sessionAuthenticator: SessionAuthenticator
    let deepLinkController: DeepLinkController
    
    // MARK: - Init -
    
    init() {
        FirebaseApp.configure()
        
        self.abacus = Abacus()
        self.exchange = Exchange(client: client)
        self.contentController = ContentController(client: client)
        self.sessionAuthenticator = SessionAuthenticator(
            client: client,
            exchange: exchange,
            cameraSession: cameraSession,
            bannerController: bannerController,
            reachability: reachability,
            betaFlags: betaFlags,
            abacus: abacus
        )
        self.deepLinkController = DeepLinkController(sessionAuthenticator: sessionAuthenticator, abacus: abacus)
        self.pushController = PushController(sessionAuthenticator: sessionAuthenticator, client: client)
        
//        betaFlags.setAccessGranted(true)
    }
    
    func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(client)
        
            .environmentObject(cameraSession)
            .environmentObject(cameraAuthorizer)
            .environmentObject(betaFlags)
            .environmentObject(notificationController)
            .environmentObject(statusController)
            .environmentObject(bannerController)
            .environmentObject(reachability)
            .environmentObject(biometrics)

            .environmentObject(abacus)
            .environmentObject(exchange)
            .environmentObject(contentController)
            .environmentObject(pushController)
            .environmentObject(sessionAuthenticator)
    }
    
    static func installationID() async throws -> String {
        try await Installations.installations().installationID()
    }
}

// MARK: - Mark -

extension AppContainer {
    static var mock: AppContainer {
        (UIApplication.shared.delegate as! AppDelegate).appContainer
    }
}
