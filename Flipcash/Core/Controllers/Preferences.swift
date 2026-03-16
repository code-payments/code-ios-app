//
//  Preferences.swift
//  Code
//
//  Created by Dima Bart on 2022-09-08.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// User-facing preferences persisted to `UserDefaults`.
///
/// Currently manages camera auto-start behavior. When
/// ``cameraAutoStartDisabled`` is toggled, the camera is also
/// disabled on background entry to avoid unexpected activation.
///
/// Inject via `@Environment(Preferences.self)`.
@MainActor @Observable
class Preferences {

    /// Whether the camera feed is currently active.
    /// Derived from ``cameraAutoStartDisabled`` and reset on background entry.
    var cameraEnabled: Bool = false

    /// When `true`, the camera won't start automatically on app launch.
    /// Persisted to `UserDefaults` and synced to ``cameraEnabled`` via `willSet`.
    var cameraAutoStartDisabled: Bool = false {
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
    
    /// Called from the app delegate when entering background.
    /// Disables the camera if the user has opted out of auto-start.
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
