//
//  CNAuthorizationStatus+ContactAccess.swift
//  Flipcash
//

import Contacts

extension CNAuthorizationStatus {

    /// `true` when the app may read contacts — full (`.authorized`) or partial
    /// (`.limited`, iOS 18+). `.limited` is matched only as a `switch` pattern,
    /// never used as a value, so this compiles on the iOS 17 deployment target
    /// where `.limited` is unavailable as an expression.
    ///
    /// `nonisolated` so the off-main sync gate (`ContactSyncController.runSync`)
    /// and bootstrap `Task.detached` can read it under main-actor-by-default
    /// isolation.
    nonisolated var allowsContactAccess: Bool {
        switch self {
        case .authorized, .limited:
            true
        case .notDetermined, .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}
