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

class Container {
    
    let client: Client
    let flipClient: FlipClient
    let accountManager: AccountManager
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
        self.betaFlags              = BetaFlags.shared
        self.preferences            = Preferences()
        self.notificationController = NotificationController()
        
        _ = sessionAuthenticator
    }
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(client)
            .environmentObject(flipClient)
            .environment(sessionAuthenticator)
            .environment(betaFlags)
            .environment(preferences)
            .environment(notificationController)
    }
    
    static func configureFirebase() {
        let isRunningPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if !isRunningPreviews && !isRunningUnitTests {
            FirebaseApp.configure()
        }
    }

    /// Unit tests run the app inside the test runner process where
    /// `XCTestConfigurationFilePath` is set. UI tests run a separate app
    /// process that does not inherit that var, so this stays `false` there.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// UI tests launch the app with `--ui-testing` so the host process can
    /// suppress animations, telemetry, and other production-only side effects.
    static var isRunningUITests: Bool {
        CommandLine.arguments.contains("--ui-testing")
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
