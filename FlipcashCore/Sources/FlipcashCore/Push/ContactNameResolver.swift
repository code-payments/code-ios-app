//
//  ContactNameResolver.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI

/// Read access to the on-device contact snapshot keyed by E.164.
public protocol ContactSnapshotReading: Sendable {
    /// Returns the CNContact identifier(s) the snapshot has for this phone, or empty.
    func contactIds(forE164 e164: String) throws -> [String]
}

/// Resolves a CNContact identifier to a display name.
public protocol ContactNameProviding: Sendable {
    /// Returns a non-empty display name for the contact, or `nil` if not found
    /// or the name is empty.
    func displayName(forContactId id: String) -> String?
}

/// Resolves an E.164 phone number to the user's local contact name.
public final class ContactNameResolver: Sendable {

    private let snapshotReader: any ContactSnapshotReading
    private let nameProvider: any ContactNameProviding

    public init(snapshotReader: any ContactSnapshotReading, nameProvider: any ContactNameProviding) {
        self.snapshotReader = snapshotReader
        self.nameProvider = nameProvider
    }

    /// Returns the first non-empty display name from any contact tied to the
    /// phone, or `nil` if no contact matches or none have a non-empty name.
    public func resolve(phone: Flipcash_Phone_V1_PhoneNumber) -> String? {
        let contactIds = (try? snapshotReader.contactIds(forE164: phone.value)) ?? []
        for id in contactIds {
            if let name = nameProvider.displayName(forContactId: id) {
                return name
            }
        }
        return nil
    }
}
