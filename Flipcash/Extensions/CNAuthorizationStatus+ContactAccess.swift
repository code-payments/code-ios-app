//
//  CNAuthorizationStatus+ContactAccess.swift
//  Flipcash
//

import Contacts

extension CNAuthorizationStatus {

    /// `true` when the app may read contacts — full (`.authorized`) or partial
    /// (`.limited`).
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
