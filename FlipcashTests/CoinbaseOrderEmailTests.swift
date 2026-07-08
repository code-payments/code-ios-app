//
//  CoinbaseOrderEmailTests.swift
//  FlipcashTests
//

import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("CoinbaseOrderEmail")
struct CoinbaseOrderEmailTests {

    private static let unverifiedProfile = Profile(
        displayName: nil,
        phone: Phone?.none,
        email: nil
    )

    @Test("A server-verified email wins regardless of the flag or local fallback")
    func verifiedEmail_alwaysWins() {
        for requireVerification in [true, false] {
            let email = CoinbaseOrderEmail.resolve(
                profile: .verifiedFixture,
                userFlags: .fixture(requireCoinbaseEmailVerification: requireVerification),
                unverifiedEmail: "local@example.com"
            )
            #expect(email == Profile.verifiedFixture.email)
        }
    }

    @Test("Verification required: a local unverified email does not satisfy")
    func verificationRequired_localEmailIgnored() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            userFlags: .fixture(requireCoinbaseEmailVerification: true),
            unverifiedEmail: "local@example.com"
        )
        #expect(email == nil)
    }

    @Test("Verification skipped: the local unverified email is used")
    func verificationSkipped_localEmailUsed() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            userFlags: .fixture(requireCoinbaseEmailVerification: false),
            unverifiedEmail: "local@example.com"
        )
        #expect(email == "local@example.com")
    }

    @Test("Verification skipped with no local email leaves the requirement unsatisfied")
    func verificationSkipped_noLocalEmail_unsatisfied() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            userFlags: .fixture(requireCoinbaseEmailVerification: false),
            unverifiedEmail: nil
        )
        #expect(email == nil)
    }

    @Test("Missing userFlags is treated as verification-required")
    func missingUserFlags_treatedAsRequired() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            userFlags: nil,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == nil)
    }
}
