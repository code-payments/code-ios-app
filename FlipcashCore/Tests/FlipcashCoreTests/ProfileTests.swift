//
//  ProfileTests.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-07.
//

import Foundation
import Testing
@testable import FlipcashCore

@Suite("Profile Tests")
struct ProfileTests {

    @Test("Empty email is normalized to nil")
    func testEmptyEmailNormalizedToNil() throws {
        let profile = try Profile(displayName: nil, phone: String?.none, email: "")
        #expect(profile.email == nil)
        #expect(profile.isEmailVerified == false)
    }

    @Test("Non-empty email is preserved")
    func testNonEmptyEmailPreserved() throws {
        let profile = try Profile(displayName: nil, phone: String?.none, email: "user@example.com")
        #expect(profile.email == "user@example.com")
        #expect(profile.isEmailVerified == true)
    }

    @Test("Nil email stays nil")
    func testNilEmailStaysNil() throws {
        let profile = try Profile(displayName: nil, phone: String?.none, email: nil)
        #expect(profile.email == nil)
        #expect(profile.isEmailVerified == false)
    }

    @Test("Empty phone is normalized to nil")
    func testEmptyPhoneNormalizedToNil() throws {
        let profile = try Profile(displayName: nil, phone: "", email: nil)
        #expect(profile.phone == nil)
        #expect(profile.isPhoneVerified == false)
    }
}
