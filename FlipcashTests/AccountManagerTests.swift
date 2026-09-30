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

    // MARK: - Switcher title -

    @Test("the title is the username's handle when the account has one")
    func title_prefersUsername() {
        let title = AccountDescription.title(
            username: Username("ted"),
            displayName: "Ted Lasso",
            fallback: "apple...zebra"
        )

        #expect(title == "@ted")
    }

    @Test("without a username the title is the display name")
    func title_fallsBackToDisplayName() {
        let title = AccountDescription.title(
            username: nil,
            displayName: "Ted Lasso",
            fallback: "apple...zebra"
        )

        #expect(title == "Ted Lasso")
    }

    @Test("without a username or display name the title is the mnemonic name", arguments: [nil, ""])
    func title_fallsBackToMnemonicName(displayName: String?) {
        let title = AccountDescription.title(
            username: nil,
            displayName: displayName,
            fallback: "apple...zebra"
        )

        #expect(title == "apple...zebra")
    }

    @Test("an entry with no cached profile is titled by its mnemonic name")
    func title_withoutCachedProfile_isMnemonicName() {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)

        #expect(manager.fetchActiveHistorical().first?.title == KeyAccount.mock.mnemonic.name)
    }

    @Test("a fetched profile retitles the row, so accounts never cached still show their username")
    func historicalAccount_setProfile_usesFetchedUsername() throws {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)
        var row = HistoricalAccount(details: try #require(manager.fetchActiveHistorical().first))
        #expect(row.title == KeyAccount.mock.mnemonic.name)

        row.setProfile(Profile(displayName: "Ted Lasso", phone: Optional<Phone>.none, email: nil, username: Username("ted")))

        #expect(row.title == "@ted")
    }

    @Test("a fetched profile with no names titles the row by its mnemonic name")
    func historicalAccount_setEmptyProfile_usesMnemonicName() throws {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)
        manager.cacheProfile(
            Profile(displayName: "Ted Lasso", phone: Optional<Phone>.none, email: nil, username: Username("ted")),
            ownerPublicKey: KeyAccount.mock.ownerPublicKey
        )
        var row = HistoricalAccount(details: try #require(manager.fetchActiveHistorical().first))

        row.setProfile(.empty)

        #expect(row.title == KeyAccount.mock.mnemonic.name)
    }

    // MARK: - Cached profile -

    /// Only the signed-in account has a session, so a row for any other account can be
    /// titled only from what was stored while that account was signed in.
    @Test("caching a profile stores its username and display name on the entry")
    func cacheProfile_storesUsernameAndDisplayName() throws {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)
        manager.cacheProfile(
            Profile(displayName: "Ted Lasso", phone: Optional<Phone>.none, email: nil, username: Username("ted")),
            ownerPublicKey: KeyAccount.mock.ownerPublicKey
        )

        let historical = try #require(manager.fetchActiveHistorical().first)
        #expect(historical.username == Username("ted"))
        #expect(historical.displayName == "Ted Lasso")
        #expect(historical.title == "@ted")
    }

    @Test("a later profile without a username clears the cached one")
    func cacheProfile_clearsRemovedUsername() throws {
        let manager = AccountManager()
        defer { manager.nukeForUITesting() }

        manager.set(keyAccount: .mock, userID: Self.userID)
        manager.cacheProfile(
            Profile(displayName: "Ted Lasso", phone: Optional<Phone>.none, email: nil, username: Username("ted")),
            ownerPublicKey: KeyAccount.mock.ownerPublicKey
        )
        manager.cacheProfile(
            Profile(displayName: "Ted Lasso", phone: Optional<Phone>.none, email: nil),
            ownerPublicKey: KeyAccount.mock.ownerPublicKey
        )

        let historical = try #require(manager.fetchActiveHistorical().first)
        #expect(historical.username == nil)
        #expect(historical.title == "Ted Lasso")
    }

    @Test("an entry written before profiles were cached still decodes, with no username or display name")
    func decode_entryWithoutProfile_succeeds() throws {
        let legacy = """
        {
          "account": \(String(data: try JSONEncoder().encode(KeyAccount.mock), encoding: .utf8)!),
          "creationDate": 0,
          "lastSeen": 0
        }
        """

        let decoded = try JSONDecoder().decode(AccountDescription.self, from: Data(legacy.utf8))

        #expect(decoded.username == nil)
        #expect(decoded.displayName == nil)
    }
}
