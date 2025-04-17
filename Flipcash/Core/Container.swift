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
    
    lazy var ratesController = RatesController(container: self)
    lazy var sessionAuthenticator = SessionAuthenticator(container: self)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        self.client         = Client(network: .mainNet)
        self.flipClient     = FlipClient(network: .mainNet)
        self.database       = try! Database(url: .dataStore())
        self.accountManager = AccountManager()
        
        _ = ratesController
        _ = sessionAuthenticator
    }
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(sessionAuthenticator)
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
