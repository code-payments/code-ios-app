//
//  Container.swift
//  Code
//
//  Created by Dima Bart on 2025-04-01.
//

import Foundation
import FlipcashUI
import FlipcashCore

@MainActor
class Container {
    
    let client: Client
    let database: Database
    let accountManager: AccountManager
    
    lazy var ratesController = RatesController(container: self)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        self.client         = Client(network: .mainNet)
        self.database       = try! Database(url: .dataStore())
        self.accountManager = AccountManager()
        
        _ = ratesController
        
    }
}

extension Container {
    static let mock = Container()
}
