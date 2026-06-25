//
//  SharedKeychainMigration.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

private nonisolated let logger = Logger(label: "flipcash.shared-keychain-migration")

/// One-time migration that copies the owner key into the shared keychain access group so a
/// notification extension in the same group can read it. Non-destructive — it only adds the
/// shared-group copy and leaves the legacy item, so existing users aren't logged out.
enum SharedKeychainMigration {

    /// Copies the owner key from the legacy groupless location into the shared
    /// access group when it isn't already there. Idempotent: a no-op when the
    /// key is already in the shared group or absent everywhere.
    nonisolated static func migrateOwnerKeyIfNeeded() {
        guard let sharedGroup = Keychain.sharedAccessGroup else {
            logger.warning("Shared access group unavailable, skipping owner-key migration")
            return
        }

        migrateIfNeeded(key: SecureKey.currentUserAccount.rawValue, sharedGroup: sharedGroup)
    }

    /// Copies the value at `key` from the legacy groupless location into
    /// `sharedGroup` when it isn't already there. Idempotent.
    nonisolated static func migrateIfNeeded(key: String, sharedGroup: String) {
        // Already migrated.
        guard Keychain.data(for: key, accessGroup: sharedGroup) == nil else {
            return
        }

        // Nothing to migrate.
        guard let legacyData = Keychain.data(for: key) else {
            return
        }

        let didStore = Keychain.set(legacyData, for: key, accessGroup: sharedGroup)
        logger.info("Migrated owner key into shared access group", metadata: [
            "succeeded": "\(didStore)"
        ])
    }
}
