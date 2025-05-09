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
    let accountManager: AccountManager
    let storeController: StoreController
    
    lazy var sessionAuthenticator = SessionAuthenticator(container: self)
    lazy var deepLinkController   = DeepLinkController(sessionAuthenticator: sessionAuthenticator)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        self.client          = Client(network: .mainNet)
        self.flipClient      = FlipClient(network: .mainNet)
        self.accountManager  = AccountManager()
        self.storeController = StoreController(client: flipClient)
        
        _ = sessionAuthenticator
    }
    
    fileprivate func injectingEnvironment<SomeView>(into view: SomeView) -> some View where SomeView: View {
        view
            .environmentObject(client)
            .environmentObject(flipClient)
            .environmentObject(sessionAuthenticator)
            .environmentObject(storeController)
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
