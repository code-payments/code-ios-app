//
//  SharedKeychainMigrationTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Proves the zero-logout guarantee of routing the owner key through the
/// shared keychain access group.
///
/// Once the app declares `keychain-access-groups`, the *default* group for
/// groupless writes becomes the first listed group (`...com.flipcash.shared`),
/// so a test can't model a legacy item with a plain groupless write — it would
/// land in the shared group. These tests instead write the legacy item into
/// the runtime-derived application-identifier group (`<prefix>.<bundleId>`),
/// faithfully reproducing an existing user's pre-migration owner key.
@Suite("Shared Keychain Migration", .serialized)
struct SharedKeychainMigrationTests {

    // A unique, test-only key. Never `.currentUserAccount`, so the real
    // owner-key state is never touched. Each test cleans up all variants.
    private static func uniqueKey() -> String {
        "com.flipcash.tests.sharedKeychain.\(UUID().uuidString)"
    }

    /// The shared access group, resolved at runtime. Skips the test cleanly if
    /// the simulator keychain can't resolve it.
    private func sharedGroup() throws -> String {
        try #require(
            Keychain.sharedAccessGroup,
            "Shared access group must resolve at runtime"
        )
    }

    /// The legacy application-identifier access group an existing user's owner
    /// key lives in (`<teamPrefix>.<bundleId>`), derived at runtime — never
    /// hardcoded. This is the group groupless writes used *before* the
    /// `keychain-access-groups` entitlement existed.
    private func legacyGroup() throws -> String {
        let shared = try sharedGroup()
        let prefix = try #require(shared.split(separator: ".").first.map(String.init))
        let bundleId = try #require(Bundle.main.bundleIdentifier)
        return "\(prefix).\(bundleId)"
    }

    private func cleanup(_ key: String, groups: [String]) {
        Keychain.delete(key)
        for group in groups {
            Keychain.delete(key, accessGroup: group)
        }
    }

    // MARK: - Zero-logout: legacy item is still recoverable -

    @Test("A legacy item is recovered by the groupless fallback read")
    func legacyItemRecoveredByGrouplessFallback() throws {
        let shared = try sharedGroup()
        let legacy = try legacyGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared, legacy]) }

        // Simulate an existing user's owner key, written to the legacy
        // application-identifier group before the shared-group entitlement.
        let payload = Data("legacy-owner-key".utf8)
        #expect(Keychain.set(payload, for: key, accessGroup: legacy))

        // The shared-group read misses (the item predates the migration)...
        #expect(Keychain.data(for: key, accessGroup: shared) == nil)
        // ...but the groupless fallback read recovers it. This is the
        // zero-logout guarantee: the user authenticates on upgrade.
        #expect(Keychain.data(for: key) == payload)
    }

    // MARK: - Shared group round trip -

    @Test("Data written to the shared group reads back from the shared group")
    func sharedGroupRoundTrip() throws {
        let shared = try sharedGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared]) }

        let payload = Data("shared-owner-key".utf8)
        #expect(Keychain.set(payload, for: key, accessGroup: shared))
        #expect(Keychain.data(for: key, accessGroup: shared) == payload)
    }

    // MARK: - Migration: copy legacy → shared, idempotent -

    @Test("Migration copies a legacy value into the shared group")
    func migrationCopiesLegacyIntoSharedGroup() throws {
        let shared = try sharedGroup()
        let legacy = try legacyGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared, legacy]) }

        let payload = Data("legacy-owner-key".utf8)
        #expect(Keychain.set(payload, for: key, accessGroup: legacy))

        // Pre-condition: absent from the shared group.
        #expect(Keychain.data(for: key, accessGroup: shared) == nil)

        SharedKeychainMigration.migrateIfNeeded(key: key, sharedGroup: shared)

        // Copied into the shared group, and the legacy item is preserved.
        #expect(Keychain.data(for: key, accessGroup: shared) == payload)
        #expect(Keychain.data(for: key, accessGroup: legacy) == payload)
    }

    @Test("Running the migration again is a no-op")
    func migrationIsIdempotent() throws {
        let shared = try sharedGroup()
        let legacy = try legacyGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared, legacy]) }

        let payload = Data("legacy-owner-key".utf8)
        #expect(Keychain.set(payload, for: key, accessGroup: legacy))

        SharedKeychainMigration.migrateIfNeeded(key: key, sharedGroup: shared)
        // Second run must not throw, duplicate, or clear the value.
        SharedKeychainMigration.migrateIfNeeded(key: key, sharedGroup: shared)

        #expect(Keychain.data(for: key, accessGroup: shared) == payload)
        #expect(Keychain.data(for: key, accessGroup: legacy) == payload)
    }

    @Test("Migration is a no-op when the legacy value is absent")
    func migrationNoOpWhenAbsent() throws {
        let shared = try sharedGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared]) }

        SharedKeychainMigration.migrateIfNeeded(key: key, sharedGroup: shared)

        #expect(Keychain.data(for: key, accessGroup: shared) == nil)
    }

    // MARK: - Logout clears every group (no resurrection) -

    @Test("Logout teardown clears both the shared and legacy copies")
    func logoutClearsAllGroups() throws {
        let shared = try sharedGroup()
        let legacy = try legacyGroup()
        let key = Self.uniqueKey()
        defer { cleanup(key, groups: [shared, legacy]) }

        // A migrated owner key exists in both the legacy and shared groups.
        let payload = Data("owner-key".utf8)
        #expect(Keychain.set(payload, for: key, accessGroup: legacy))
        #expect(Keychain.set(payload, for: key, accessGroup: shared))

        // Production logout teardown for a shared-group key: delete the shared
        // copy, then a groupless delete that spans every accessible group.
        Keychain.delete(key, accessGroup: shared)
        Keychain.delete(key)

        // Nothing survives — the fallback read can't resurrect a stale copy.
        #expect(Keychain.data(for: key, accessGroup: shared) == nil)
        #expect(Keychain.data(for: key, accessGroup: legacy) == nil)
        #expect(Keychain.data(for: key) == nil)
    }
}
