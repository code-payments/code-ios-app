//
//  Container.swift
//  Code
//
//  Created by Dima Bart on 2025-04-01.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

@MainActor
class Container {
    
    let client: Client
    let flipClient: FlipClient
    let database: Database
    let accountManager: AccountManager
    
    lazy var ratesController      = RatesController(container: self)
    lazy var sessionAuthenticator = SessionAuthenticator(container: self)
    lazy var deepLinkController   = DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        try? Self.createApplicationSupportIfNeeded()
        
        self.client         = Client(network: .mainNet)
        self.flipClient     = FlipClient(network: .mainNet)
        self.database       = try! Self.initializeDatabase()
        self.accountManager = AccountManager()
        
        _ = ratesController
        _ = sessionAuthenticator
    }
    
    private static func initializeDatabase() throws -> Database {
        // Currently we don't do migrations so every time
        // the user version is outdated, we'll rebuild the
        // database during sync.
        let userVersion = (try? Database.userVersion()) ?? 0
        let currentVersion = try InfoPlist.value(for: "SQLiteVersion").integer()
        if currentVersion > userVersion {
            try Database.deleteStore()
            trace(.failure, components: "Outdated user version, deleted database.")
            try Database.setUserVersion(version: currentVersion)
        }
        
        return try Database(url: .dataStore())
    }
    
    private static func createApplicationSupportIfNeeded() throws {
        if !FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.path) {
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory,
                withIntermediateDirectories: false
            )
        }
    }
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(client)
            .environmentObject(flipClient)
            .environmentObject(sessionAuthenticator)
            .environmentObject(ratesController)
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
