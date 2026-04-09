//
//  AccountInfoTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
import FlipcashAPI

@Suite("AccountInfo self-claim parsing")
struct AccountInfoSelfClaimTests {

    @Test("isGiftCardIssuer round-trips proto value", arguments: [false, true])
    func roundTrips(_ value: Bool) throws {
        var proto = makeMinimalTokenAccountInfo()
        proto.isGiftCardIssuer = value
        let info = try AccountInfo(proto)
        #expect(info.isGiftCardIssuer == value)
    }

    // MARK: - Helpers -

    /// Builds a `Ocp_Account_V1_TokenAccountInfo` populated with just enough
    /// fields for `AccountInfo.init(_:)` to succeed: every `SolanaAccountId`
    /// the parser reads must contain a valid 32-byte public key, otherwise
    /// `PublicKey(_:)` throws.
    private func makeMinimalTokenAccountInfo() -> Ocp_Account_V1_TokenAccountInfo {
        let id = PublicKey.mock.solanaAccountID
        var proto = Ocp_Account_V1_TokenAccountInfo()
        proto.address = id
        proto.mint = id
        proto.owner = id
        proto.authority = id
        return proto
    }
}
