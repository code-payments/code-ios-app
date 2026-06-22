//
//  OwnerKeyStoreTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("OwnerKeyStore", .serialized)
struct OwnerKeyStoreTests {

    /// A `UserAccount` built from the shared mock mnemonic — stable across
    /// test runs and identical to what `@SecureCodable` persists.
    private static let mockAccount = UserAccount(
        userID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        keyAccount: .mock
    )

    private func sharedGroup() throws -> String {
        try #require(
            Keychain.sharedAccessGroup,
            "Shared access group must resolve at runtime"
        )
    }

    // MARK: - Round-trip -

    @Test("loadOwnerAccount returns the correct UserAccount after a shared-group write")
    func loadOwnerAccount_sharedGroupWrite_returnsCorrectAccount() throws {
        let group = try sharedGroup()
        defer { Keychain.delete(OwnerKeyStore.ownerAccountKey, accessGroup: group) }

        let data = try JSONEncoder().encode(Self.mockAccount)
        #expect(Keychain.set(data, for: OwnerKeyStore.ownerAccountKey, accessGroup: group))

        let loaded = OwnerKeyStore.loadOwnerAccount()
        #expect(loaded?.userID == Self.mockAccount.userID)
        #expect(loaded?.keyAccount.owner.publicKey == Self.mockAccount.keyAccount.owner.publicKey)
    }

    @Test("loadOwnerKeyPair returns the correct public key after a shared-group write")
    func loadOwnerKeyPair_sharedGroupWrite_returnsCorrectPublicKey() throws {
        let group = try sharedGroup()
        defer { Keychain.delete(OwnerKeyStore.ownerAccountKey, accessGroup: group) }

        let data = try JSONEncoder().encode(Self.mockAccount)
        #expect(Keychain.set(data, for: OwnerKeyStore.ownerAccountKey, accessGroup: group))

        let loaded = OwnerKeyStore.loadOwnerKeyPair()
        #expect(loaded?.publicKey == Self.mockAccount.keyAccount.owner.publicKey)
    }

    @Test("loadOwnerKeyPair returns nil when no account is stored")
    func loadOwnerKeyPair_noAccount_returnsNil() throws {
        let group = try sharedGroup()
        // Ensure the key is absent before the call.
        Keychain.delete(OwnerKeyStore.ownerAccountKey, accessGroup: group)
        defer { Keychain.delete(OwnerKeyStore.ownerAccountKey, accessGroup: group) }

        #expect(OwnerKeyStore.loadOwnerKeyPair() == nil)
    }

    // MARK: - Drift guard -

    @Test("ownerAccountKey matches SecureKey.currentUserAccount.rawValue")
    func ownerAccountKey_matchesSecureKey() {
        #expect(OwnerKeyStore.ownerAccountKey == SecureKey.currentUserAccount.rawValue)
    }
}
