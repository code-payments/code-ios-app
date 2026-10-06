//
//  AccountInfoDetailsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@Suite("AccountInfoDetails")
struct AccountInfoDetailsTests {

    private let userID = UUID()
    private let authority = PublicKey.usdc

    private func profile(phone: Phone?, email: String?) -> Profile {
        Profile(displayName: "Ada", phone: phone, email: email)
    }

    @Test("All fields present: phone, email, account ID, public key in order")
    func allFields() throws {
        let phone = try #require(Phone("+14155552671"))
        let rows = AccountInfoDetails.rows(
            profile: profile(phone: phone, email: "ada@example.com"),
            userID: userID,
            authority: authority
        )

        #expect(rows.map(\.title) == ["Phone", "Email", "Account ID", "Public Key"])
        #expect(rows.map(\.display) == [phone.national, "ada@example.com", userID.uuidString, authority.base58])
        #expect(rows.map(\.accessibilityID) == [
            "account-info-phone", "account-info-email", "account-info-account-id", "account-info-public-key",
        ])
    }

    @Test("Phone copies the E.164 form, not the national display")
    func phoneCopiesE164() throws {
        let phone = try #require(Phone("+14155552671"))
        let rows = AccountInfoDetails.rows(
            profile: profile(phone: phone, email: nil),
            userID: userID,
            authority: authority
        )

        let row = try #require(rows.first)
        #expect(row.copyValue == phone.e164)
        #expect(row.display == phone.national)
    }

    @Test("No phone and no email leaves account ID and public key")
    func noContact() {
        let rows = AccountInfoDetails.rows(
            profile: profile(phone: nil, email: nil),
            userID: userID,
            authority: authority
        )

        #expect(rows.map(\.title) == ["Account ID", "Public Key"])
        #expect(rows.map(\.copyValue) == [userID.uuidString, authority.base58])
    }

    @Test("An empty email string yields no email row")
    func emptyEmail() {
        let rows = AccountInfoDetails.rows(
            profile: profile(phone: nil, email: ""),
            userID: userID,
            authority: authority
        )

        #expect(!rows.contains { $0.title == "Email" })
    }

    @Test("A missing profile still shows account ID and public key")
    func nilProfile() {
        let rows = AccountInfoDetails.rows(profile: nil, userID: userID, authority: authority)

        #expect(rows.map(\.title) == ["Account ID", "Public Key"])
    }
}
