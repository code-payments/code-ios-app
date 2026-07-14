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
    }

    @Test("Empty phone is normalized to nil")
    func testEmptyPhoneNormalizedToNil() throws {
        let profile = try makeProfile(phone: "")
        #expect(profile.phone == nil)
        #expect(profile.isPhoneVerified == false)
    }

    @Test("Newly linked phone is detected only on a fresh number")
    func newlyLinkedPhone_detectsTransitions() throws {
        let none = try makeProfile(phone: nil)
        let x    = try makeProfile(phone: "+14155550100")
        let y    = try makeProfile(phone: "+14155550101")

        #expect(x.hasNewlyLinkedPhone(since: nil)  == true)  // first ever
        #expect(x.hasNewlyLinkedPhone(since: none) == true)  // no prior number
        #expect(x.hasNewlyLinkedPhone(since: x)    == false) // same number (relaunch)
        #expect(x.hasNewlyLinkedPhone(since: y)    == true)  // number changed
        #expect(none.hasNewlyLinkedPhone(since: x) == false) // number removed
    }
}

private func makeProfile(email: String? = nil, phone: String? = nil) throws -> Profile {
    try Profile(displayName: nil, phone: phone, email: email)
}
