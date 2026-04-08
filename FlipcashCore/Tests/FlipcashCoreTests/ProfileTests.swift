//
//  ProfileTests.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-07.
//

import Testing
import FlipcashCore

@Suite("Profile Tests")
struct ProfileTests {

    @Test("Email is normalized",
          arguments: [
              (input: nil,                expected: nil),
              (input: "",                 expected: nil),
              (input: "user@example.com", expected: "user@example.com"),
          ] as [(input: String?, expected: String?)])
    func testEmailNormalization(input: String?, expected: String?) throws {
        let profile = try makeProfile(email: input)
        #expect(profile.email == expected)
        #expect(profile.isEmailVerified == (expected != nil))
    }

    @Test("Empty phone is normalized to nil")
    func testEmptyPhoneNormalizedToNil() throws {
        let profile = try makeProfile(phone: "")
        #expect(profile.phone == nil)
        #expect(profile.isPhoneVerified == false)
    }
}

private func makeProfile(email: String? = nil, phone: String? = nil) throws -> Profile {
    try Profile(displayName: nil, phone: phone, email: email)
}
