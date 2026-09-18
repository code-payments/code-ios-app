//
//  AccountManagerTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AccountManager", .serialized)
@MainActor
struct AccountManagerTests {

    private static let userID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    // MARK: - Historical user ID -

    /// Launch reaches the tabs without a network round trip only if the historical entry
    /// carries the user ID. Without it, the only way back to a `UserAccount` is
    /// `login(owner:)`, which is what put a server call in front of the wallet screen.
    @Test("a stored account keeps its user ID in the historical list")
    func set_storesUserIDOnHistoricalEntry() {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)

        let historical = manager.fetchActiveHistorical().first
        #expect(historical?.account.ownerPublicKey == KeyAccount.mock.ownerPublicKey)
        #expect(historical?.userID == Self.userID)
    }

    /// The same account seen again must not drop the user ID it already had — `upsert`
    /// rewrites the entry in place on every launch.
    @Test("re-seeing an account keeps the user ID already stored for it")
    func upsert_preservesStoredUserID() {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)
        manager.upsert(keyAccount: .mock)

        #expect(manager.fetchActiveHistorical().first?.userID == Self.userID)
    }

    /// Entries written before the user ID was stored are still in people's keychains, so
    /// decoding one must succeed and report the absence rather than failing outright.
    @Test("an entry written before user IDs were stored still decodes")
    func decode_entryWithoutUserID_succeeds() throws {
        let legacy = """
        {
          "account": \(String(data: try JSONEncoder().encode(KeyAccount.mock), encoding: .utf8)!),
          "creationDate": 0,
          "lastSeen": 0
        }
        """

        let decoded = try JSONDecoder().decode(AccountDescription.self, from: Data(legacy.utf8))

        #expect(decoded.userID == nil)
        #expect(decoded.account.ownerPublicKey == KeyAccount.mock.ownerPublicKey)
    }
}
