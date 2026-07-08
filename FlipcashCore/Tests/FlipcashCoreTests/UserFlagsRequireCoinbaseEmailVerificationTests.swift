//
//  UserFlagsRequireCoinbaseEmailVerificationTests.swift
//  FlipcashCoreTests
//

import Testing
@testable import FlipcashCore
import FlipcashAPI

@Suite("UserFlags.requireCoinbaseEmailVerification")
struct UserFlagsRequireCoinbaseEmailVerificationTests {

    @Test("Maps requireCoinbaseEmailVerification from the proto")
    func requireCoinbaseEmailVerification_mapsFromProto() {
        let required = UserFlags(Flipcash_Account_V1_UserFlags.with { $0.requireCoinbaseEmailVerification = true })
        #expect(required.requireCoinbaseEmailVerification)

        let unset = UserFlags(Flipcash_Account_V1_UserFlags())
        #expect(unset.requireCoinbaseEmailVerification == false)
    }
}
