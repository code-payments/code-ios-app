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
    
    let client = Client(network: .mainNet)
    
    let cameraSession = CameraSession<CodeExtractor>()
    
    // MARK: - Init -
    
    init() {
        
    }
}

extension Container {
    static let mock = Container()
}
