//
//  SharedDefaults.swift
//  FlipcashCore
//

import Foundation

/// Shared between the main app and the NotificationService extension.
public enum SharedDefaults {

    private nonisolated(unsafe) static let store: UserDefaults = {
        guard let store = UserDefaults(suiteName: AppGroup.id) else {
            preconditionFailure("Missing app-group entitlement: \(AppGroup.id)")
        }
        return store
    }()

    private enum Key {
        static let currentOwnerBase58 = "flipcash.currentOwnerBase58"
    }

    /// Base58 of the currently logged-in owner's authority public key. `nil` when logged out.
    public static var currentOwnerBase58: String? {
        get { store.string(forKey: Key.currentOwnerBase58) }
        set { store.set(newValue, forKey: Key.currentOwnerBase58) }
    }
}
