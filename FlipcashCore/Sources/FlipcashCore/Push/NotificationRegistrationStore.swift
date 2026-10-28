//
//  NotificationRegistrationStore.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Keeps the last `AddToken` outcome for one account, so the notification status page can report
/// it and soften a transport failure. Never stores the token itself.
public final class NotificationRegistrationStore {

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, owner: PublicKey) {
        self.defaults = defaults
        self.key = "flipcash-\(owner.base58)-notification-registration"
    }

    /// The saved outcome. Unreadable data is treated as none.
    public var record: NotificationStatus.RegistrationRecord? {
        get {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(NotificationStatus.RegistrationRecord.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }

    /// Removes the saved outcome. Called on logout.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
