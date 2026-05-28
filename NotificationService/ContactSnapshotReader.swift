//
//  ContactSnapshotReader.swift
//  NotificationService
//

import Foundation
import FlipcashCore
import SQLite

/// Read-only access to the `local_contacts_snapshot` table in the shared
/// SQLite store. Opens a fresh connection per call; the extension is
/// short-lived so connection reuse isn't worth the lifetime management.
struct ContactSnapshotReader: ContactSnapshotReading {

    let storeURL: URL

    func contactIds(forE164 e164: String) throws -> [String] {
        let connection = try Connection(storeURL.path, readonly: true)
        connection.busyTimeout = 1000
        let statement = try connection.prepare(
            "SELECT contactId FROM local_contacts_snapshot WHERE e164 = ?",
            e164
        )
        return statement.compactMap { row in
            row[0] as? String
        }
    }
}
