//
//  ProfileTests.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-07.
//

import Foundation
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

    /// Profiles persist as a JSON blob in a single-row table, so adding
    /// `profilePicture` is only safe if rows written before it still decode.
    /// This is the whole reason the change ships without a `SQLiteVersion` bump.
    @Test("A row persisted before profile pictures still decodes")
    func decodesProfilePersistedBeforeProfilePictures() throws {
        let legacy = Data(#"{"displayName":"Ted Livingston","email":"ted@example.com"}"#.utf8)

        let profile = try JSONDecoder().decode(Profile.self, from: legacy)

        #expect(profile.displayName == "Ted Livingston")
        #expect(profile.email == "ted@example.com")
        #expect(profile.phone == nil)
        #expect(profile.profilePicture == nil)
        #expect(profile.isTippable == false)
    }

    @Test("A profile needs both a name and a picture to receive tips",
          arguments: [
              (name: "Ted", hasPicture: true,  expected: true),
              (name: "Ted", hasPicture: false, expected: false),
              (name: nil,   hasPicture: true,  expected: false),
              (name: "",    hasPicture: true,  expected: false),
          ] as [(name: String?, hasPicture: Bool, expected: Bool)])
    func isTippableRequiresNameAndPicture(name: String?, hasPicture: Bool, expected: Bool) {
        let picture = ProfilePicture(
            blobID: .mock,
            thumbnailURL: URL(string: "https://cdn.example.com/thumb"),
            displayURL: URL(string: "https://cdn.example.com/display"),
            expiresAt: nil
        )

        let profile = Profile(
            displayName: name,
            phone: Optional<Phone>.none,
            email: nil,
            profilePicture: hasPicture ? picture : nil
        )

        #expect(profile.isTippable == expected)
    }
}

private func makeProfile(email: String? = nil, phone: String? = nil) throws -> Profile {
    try Profile(displayName: nil, phone: phone, email: email)
}
