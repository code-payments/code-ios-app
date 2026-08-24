//
//  ProfileTests.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-04-07.
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

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

    /// The blobs are the whole picture, so a stored profile round-trips to an
    /// equal one — nothing has to be re-fetched to make it usable again.
    @Test("A stored profile round-trips its picture blobs")
    func persistingAProfileKeepsTheBlobs() throws {
        // A distinct thumbnail blob, so a dropped one can't pass as the original.
        let thumbnail = BlobID(uuid: UUID(uuidString: "6f9619ff-8b86-d011-b42d-00cf4fc964ff")!)
        let picture = ProfilePicture(blobID: .mock, thumbnailBlobID: thumbnail)
        let profile = Profile(displayName: "Ted", phone: Optional<Phone>.none, email: nil, profilePicture: picture)

        let restored = try JSONDecoder().decode(
            Profile.self,
            from: try JSONEncoder().encode(profile)
        )

        #expect(restored.profilePicture == picture)
        #expect(restored.isTippable)
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
        // A name-only profile is tippable — a picture is not required.
        #expect(profile.isTippable == true)
    }

    /// A fixture, not a round-trip: a round-trip passes even if the key names
    /// change together, which is exactly the break that empties every stored row.
    @Test("A stored picture decodes from its on-disk keys")
    func decodesPictureFromStoredKeys() throws {
        let stored = Data(#"""
        {"displayName":"Ted","profilePicture":{"blobID":{"data":"AQIDBAUGBwgJCgsMDQ4PEA=="},"thumbnailBlobID":{"data":"EA8ODQwLCgkIBwYFBAMCAQ=="}}}
        """#.utf8)

        let profile = try JSONDecoder().decode(Profile.self, from: stored)
        let picture = try #require(profile.profilePicture)

        #expect(picture.blobID.data == Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]))
        #expect(picture.thumbnailBlobID.data == Data([16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]))
        #expect(profile.isTippable)
    }

    /// An earlier build on this branch stored the blob alone. Rows persist as one
    /// JSON blob, so throwing here would empty the whole profile.
    @Test("A picture stored without a thumbnail falls back to the original")
    func decodesPictureWithoutAThumbnail() throws {
        let stored = Data(#"""
        {"displayName":"Ted","profilePicture":{"blobID":{"data":"AQIDBAUGBwgJCgsMDQ4PEA=="}}}
        """#.utf8)

        let profile = try JSONDecoder().decode(Profile.self, from: stored)
        let picture = try #require(profile.profilePicture)

        #expect(picture.thumbnailBlobID == picture.blobID)
        #expect(profile.isTippable)
    }

    @Test("A profile needs only a non-empty name to receive tips — a picture is not required",
          arguments: [
              (name: "Ted", hasPicture: true,  expected: true),
              (name: "Ted", hasPicture: false, expected: true),
              (name: nil,   hasPicture: true,  expected: false),
              (name: nil,   hasPicture: false, expected: false),
              (name: "",    hasPicture: false, expected: false),
          ] as [(name: String?, hasPicture: Bool, expected: Bool)])
    func isTippableRequiresName(name: String?, hasPicture: Bool, expected: Bool) {
        let picture = ProfilePicture(blobID: .mock, thumbnailBlobID: .mock)

        let profile = Profile(
            displayName: name,
            phone: Optional<Phone>.none,
            email: nil,
            profilePicture: hasPicture ? picture : nil
        )

        #expect(profile.isTippable == expected)
    }

    @Test("Tip card customization round-trips")
    func tipCardCustomizationRoundTrips() throws {
        let profile = Profile(
            displayName: "Ted",
            phone: Optional<Phone>.none,
            email: nil,
            tipCardCustomization: TipCardCustomization(colorHex: "#19191A")
        )

        let restored = try JSONDecoder().decode(
            Profile.self,
            from: try JSONEncoder().encode(profile)
        )

        #expect(restored.tipCardCustomization?.colorHex == "#19191A")
    }

    /// The signed-in user's profile persists as a JSON blob; `tipCardCustomization`
    /// is optional so rows written before it still decode (to a nil customization).
    @Test("A row persisted before tip card customization still decodes")
    func decodesProfilePersistedBeforeTipCard() throws {
        let legacy = Data(#"{"displayName":"Ted Livingston","email":"ted@example.com"}"#.utf8)

        let profile = try JSONDecoder().decode(Profile.self, from: legacy)

        #expect(profile.displayName == "Ted Livingston")
        #expect(profile.tipCardCustomization == nil)
    }

    // MARK: - Username -

    @Test("Username round-trips")
    func usernameRoundTrips() throws {
        let profile = Profile(
            displayName: "Ted",
            phone: Optional<Phone>.none,
            email: nil,
            username: Username("ted_1")
        )

        let restored = try JSONDecoder().decode(
            Profile.self,
            from: try JSONEncoder().encode(profile)
        )

        #expect(restored.username?.value == "ted_1")
    }

    /// Profiles persist as a JSON blob, so `username` is optional and rows
    /// written before it still decode — which is why this ships without a
    /// `SQLiteVersion` bump.
    @Test("A row persisted before usernames still decodes")
    func decodesProfilePersistedBeforeUsernames() throws {
        let legacy = Data(#"{"displayName":"Ted Livingston","email":"ted@example.com"}"#.utf8)

        let profile = try JSONDecoder().decode(Profile.self, from: legacy)

        #expect(profile.displayName == "Ted Livingston")
        #expect(profile.username == nil)
    }

    /// The field is public, so it arrives on any profile the client fetches —
    /// not just the caller's own.
    @Test("A username on the proto maps onto the profile")
    func mapsUsernameFromProto() throws {
        let proto = Flipcash_Profile_V1_UserProfile.with {
            $0.displayName = "Ted"
            $0.username = .with { $0.value = "ted_1" }
        }

        #expect(try Profile(proto).username?.value == "ted_1")
    }

    /// Always set by the server, so a caller that looked the profile up by
    /// handle learns the user's id from the response.
    @Test("A user id on the proto maps onto the profile")
    func mapsUserIDFromProto() throws {
        let userID = UUID()
        let proto = Flipcash_Profile_V1_UserProfile.with {
            $0.displayName = "Ted"
            $0.userID = .with { $0.value = userID.data }
        }

        #expect(try Profile(proto).userID == userID)
    }

    @Test("A profile without a user id maps to nil")
    func mapsMissingUserIDToNil() throws {
        let proto = Flipcash_Profile_V1_UserProfile.with { $0.displayName = "Ted" }

        #expect(try Profile(proto).userID == nil)
    }

    @Test("A profile without a claimed username maps to nil")
    func mapsUnclaimedUsernameToNil() throws {
        let proto = Flipcash_Profile_V1_UserProfile.with { $0.displayName = "Ted" }

        #expect(try Profile(proto).username == nil)
    }
}

private func makeProfile(email: String? = nil, phone: String? = nil) throws -> Profile {
    try Profile(displayName: nil, phone: phone, email: email)
}
