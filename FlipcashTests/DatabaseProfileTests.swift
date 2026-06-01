//
//  DatabaseProfileTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import FlipcashCore
@testable import Flipcash

@Suite("Profile + UserFlags offline cache round-trip")
struct DatabaseProfileTests {

    private static func makeDatabase() throws -> Database {
        try Database.makeTemp()
    }

    private static let richUserFlags = UserFlags(
        isRegistered: true,
        isStaff: false,
        onrampProviders: [.coinbaseVirtual, .phantom],
        preferredOnrampProvider: .coinbaseVirtual,
        minBuildNumber: 42,
        billExchangeDataTimeout: 90,
        newCurrencyPurchaseAmount: TokenAmount(quarks: 5_000_000, mint: .usdf),
        newCurrencyFeeAmount: TokenAmount(quarks: 1_000_000, mint: .usdf),
        withdrawalFeeAmount: TokenAmount(quarks: 50_000, mint: .usdf),
        minimumHolderValue: TokenAmount(quarks: 100_000, mint: .usdf)
    )

    /// Restricted account: no onramp providers, unset timeout, zero fees.
    private static let minimalUserFlags = UserFlags(
        isRegistered: false,
        isStaff: false,
        onrampProviders: [],
        preferredOnrampProvider: .unknown,
        minBuildNumber: 0,
        billExchangeDataTimeout: nil,
        newCurrencyPurchaseAmount: .zero(mint: .usdf),
        newCurrencyFeeAmount: .zero(mint: .usdf),
        withdrawalFeeAmount: .zero(mint: .usdf),
        minimumHolderValue: .zero(mint: .usdf)
    )

    // MARK: - Empty (fresh install) -

    @Test("Empty database returns nil for profile and userFlags")
    func emptyDatabase_returnsNil() throws {
        let db = try Self.makeDatabase()
        #expect(try db.getProfile() == nil)
        #expect(try db.getUserFlags() == nil)
    }

    // MARK: - Profile -

    @Test("Profile survives an insert/read round-trip with verification flags intact")
    func profile_roundTrip_preservesFields() throws {
        let db = try Self.makeDatabase()
        let original = Profile.verifiedFixture

        try db.insertProfile(original)
        let restored = try #require(try db.getProfile())

        #expect(restored == original)
        #expect(restored.isPhoneVerified)
        #expect(restored.isEmailVerified)
    }

    @Test("Re-inserting a profile replaces the single cached row")
    func profile_insert_upsertsSingleRow() throws {
        let db = try Self.makeDatabase()

        try db.insertProfile(Profile.verifiedFixture)
        try db.insertProfile(Profile(displayName: "Updated", phone: Optional<Phone>.none, email: nil))

        let restored = try #require(try db.getProfile())
        #expect(restored.displayName == "Updated")
        #expect(!restored.isPhoneVerified)
        #expect(!restored.isEmailVerified)
    }

    // MARK: - UserFlags -

    @Test(
        "UserFlags round-trips every field",
        arguments: [DatabaseProfileTests.richUserFlags, DatabaseProfileTests.minimalUserFlags]
    )
    func userFlags_roundTrip(original: UserFlags) throws {
        let db = try Self.makeDatabase()

        try db.insertUserFlags(original)
        let restored = try #require(try db.getUserFlags())

        #expect(restored.isRegistered == original.isRegistered)
        #expect(restored.isStaff == original.isStaff)
        #expect(restored.onrampProviders == original.onrampProviders)
        #expect(restored.preferredOnrampProvider == original.preferredOnrampProvider)
        #expect(restored.hasCoinbase == original.hasCoinbase)
        #expect(restored.minBuildNumber == original.minBuildNumber)
        #expect(restored.billExchangeDataTimeout == original.billExchangeDataTimeout)
        #expect(restored.newCurrencyPurchaseAmount == original.newCurrencyPurchaseAmount)
        #expect(restored.newCurrencyFeeAmount == original.newCurrencyFeeAmount)
        #expect(restored.withdrawalFeeAmount == original.withdrawalFeeAmount)
        #expect(restored.minimumHolderValue == original.minimumHolderValue)
    }
}
