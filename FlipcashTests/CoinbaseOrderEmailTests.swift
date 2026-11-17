//
//  CoinbaseOrderEmailTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore

@MainActor
@Suite("CoinbaseOrderEmail")
struct CoinbaseOrderEmailTests {

    /// A profile whose email was linked without a code (`LinkUnverified`).
    private static let unverifiedLinked = Profile(
        displayName: "Test",
        phone: .mock,
        email: "linked@example.com",
        isEmailAddressVerified: false
    )

    /// `profile` as a row cached before `isEmailAddressVerified` existed: encoded, then
    /// stripped of that key.
    private static func cachedBeforeVerifiedFlag(_ profile: Profile) throws -> Profile {
        let data = try JSONEncoder().encode(profile)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(object.removeValue(forKey: "isEmailAddressVerified") != nil)
        let legacy = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Profile.self, from: legacy)
    }

    // MARK: - Verification required -

    @Test("Required: a server-verified email wins over the local fallback")
    func required_verifiedEmail_wins() {
        let email = CoinbaseOrderEmail.resolve(
            profile: .verifiedFixture,
            requiresVerification: true,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == Profile.verifiedFixture.email)
    }

    @Test("Required: an email linked without verification does not satisfy it")
    func required_unverifiedLinkedEmail_unsatisfied() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedLinked,
            requiresVerification: true,
            unverifiedEmail: nil
        )
        #expect(email == nil)
    }

    @Test("Required: the local unverified email does not satisfy it either")
    func required_localEmail_unsatisfied() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedLinked,
            requiresVerification: true,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == nil)
    }

    @Test("Required: the contact pair needs a verified email, not only a linked one")
    func required_contact_needsVerifiedEmail() {
        #expect(CoinbaseOrderEmail.resolveContact(profile: Self.unverifiedLinked, requiresVerification: true) == nil)
        #expect(CoinbaseOrderEmail.resolveContact(profile: .verifiedFixture, requiresVerification: true)?.email == Profile.verifiedFixture.email)
    }

    @Test("Required: a verified user whose cached profile predates the verified flag still passes")
    func required_cachedProfileBeforeFlag_passes() throws {
        let cached = try Self.cachedBeforeVerifiedFlag(.verifiedFixture)

        let email = CoinbaseOrderEmail.resolve(
            profile: cached,
            requiresVerification: true,
            unverifiedEmail: nil
        )
        #expect(email == Profile.verifiedFixture.email)
    }

    // MARK: - Verification not required -

    @Test("Not required: a linked unverified email satisfies it, as any profile email did before")
    func notRequired_unverifiedLinkedEmail_satisfies() {
        let email = CoinbaseOrderEmail.resolve(
            profile: Self.unverifiedLinked,
            requiresVerification: false,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == "linked@example.com")
    }

    @Test("Not required: without a profile email, the local unverified email is used")
    func notRequired_noProfileEmail_localEmailUsed() {
        let email = CoinbaseOrderEmail.resolve(
            profile: .empty,
            requiresVerification: false,
            unverifiedEmail: "local@example.com"
        )
        #expect(email == "local@example.com")
    }

    @Test("No email anywhere leaves the requirement unsatisfied")
    func noEmailAnywhere_unsatisfied() {
        for requiresVerification in [true, false] {
            let email = CoinbaseOrderEmail.resolve(
                profile: .empty,
                requiresVerification: requiresVerification,
                unverifiedEmail: nil
            )
            #expect(email == nil)
        }
    }
}
