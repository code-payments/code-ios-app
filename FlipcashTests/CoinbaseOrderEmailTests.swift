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

    @Test("A server-verified email wins over the local fallback")
    func verifiedEmail_wins() {
        let email = CoinbaseOrderEmail.resolve(
            profile: .verifiedFixture,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == Profile.verifiedFixture.email)
    }

    @Test("Without a verified email, the local unverified email is used")
    func noVerifiedEmail_localEmailUsed() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == "local@example.com")
    }

    @Test("No verified and no local email leaves the requirement unsatisfied")
    func noEmailAnywhere_unsatisfied() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedProfile,
            unverifiedEmail: nil
        )
        #expect(email == nil)
    }
}
