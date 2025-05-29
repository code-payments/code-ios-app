//
//  Preferences.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

@MainActor
class Preferences: ObservableObject {
    
    @Published var cameraEnabled: Bool = false
    
    @Published var cameraAutoStartDisabled: Bool = false {
        willSet {
            UserDefaults.cameraAutoStartDisabled = newValue
            cameraEnabled = !newValue
        }
    }
    
    // MARK: - Init -
    
    init() {
        cameraAutoStartDisabled = UserDefaults.cameraAutoStartDisabled ?? false
        cameraEnabled = !cameraAutoStartDisabled
    }
    
    // MARK: - Lifecycle -
    
    func appDidEnterBackground() {
        invalidateCameraIfNeeded()
    }
    
    private func invalidateCameraIfNeeded() {
        if cameraAutoStartDisabled {
            cameraEnabled = false
        }
    }
}

@MainActor
extension UserDefaults {
    @Defaults(.cameraAutoStartDisabled)
    static var cameraAutoStartDisabled: Bool?
    
    @Defaults(.cameraEnabledState)
    static var cameraEnabled: Bool?
}
