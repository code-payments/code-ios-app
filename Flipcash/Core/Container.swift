//
//  Container.swift
//  Code
//
//  Created by Dima Bart on 2025-04-01.
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import Firebase

@MainActor
class Container {
    
    let client: Client
    let flipClient: FlipClient
    let accountManager: AccountManager
    let storeController: StoreController
    let betaFlags: BetaFlags
    let preferences: Preferences
    let notificationController: NotificationController
    
    lazy var sessionAuthenticator = SessionAuthenticator(container: self)
    lazy var deepLinkController   = DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        Self.configureFirebase()
        
        self.client                 = Client(network: .mainNet)
        self.flipClient             = FlipClient(network: .mainNet)
        self.accountManager         = AccountManager()
        self.storeController        = StoreController()
        self.betaFlags              = BetaFlags.shared
        self.preferences            = Preferences()
        self.notificationController = NotificationController()
        
        _ = sessionAuthenticator
    }
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(client)
            .environmentObject(flipClient)
            .environmentObject(sessionAuthenticator)
            .environmentObject(storeController)
            .environmentObject(betaFlags)
            .environmentObject(preferences)
            .environmentObject(notificationController)
    }
    
    static func configureFirebase() {
        let isRunningPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isRunningPreviews && !isRunningTests {
            FirebaseApp.configure()
        }
    }
}

extension View {
    func injectingEnvironment(from container: Container) -> some View {
        container.injectingEnvironment(into: self)
    }
}

extension Container {
    static let mock = Container()
}
