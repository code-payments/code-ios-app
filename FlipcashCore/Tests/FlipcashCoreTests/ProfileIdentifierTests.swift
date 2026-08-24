//
//  ProfileIdentifierTests.swift
//  FlipcashCore
//

import Foundation
import Testing
import FlipcashAPI
@testable import FlipcashCore

@Suite("ProfileIdentifier Tests")
struct ProfileIdentifierTests {

    /// The wrong arm still builds a valid request, so a swap fails server-side
    /// rather than at compile time — pin each one to its oneof case.
    @Test("A user id builds the user id arm")
    func userIDBuildsItsArm() throws {
        let userID = UUID()

        guard case .userID(let proto) = ProfileIdentifier.userID(userID).proto else {
            Issue.record("Expected the userID arm")
            return
        }

        #expect(proto.value == userID.data)
    }

    @Test("A handle builds the username arm")
    func usernameBuildsItsArm() throws {
        let username = try #require(Username("ted_1"))

        guard case .username(let proto) = ProfileIdentifier.username(username).proto else {
            Issue.record("Expected the username arm")
            return
        }

        #expect(proto.value == "ted_1")
    }

    /// The arm the request carries decides which lookup the server runs, so a
    /// request built from a handle must not also read as a user-id lookup.
    @Test("Setting one arm clears the other")
    func armsAreMutuallyExclusive() throws {
        let username = try #require(Username("ted_1"))

        var request = Flipcash_Profile_V1_GetProfileRequest()
        request.identifier = ProfileIdentifier.userID(UUID()).proto
        request.identifier = ProfileIdentifier.username(username).proto

        #expect(request.username.value == "ted_1")
        #expect(request.userID.value.isEmpty)
    }

    @Test("Description tags the arm for logging")
    func descriptionTagsTheArm() throws {
        let username = try #require(Username("ted_1"))

        #expect("\(ProfileIdentifier.username(username))" == "username:ted_1")
        #expect("\(ProfileIdentifier.userID(UUID(uuidString: "da777a11-bd88-4e04-9bf5-173fb4c137a6")!))"
                == "userId:DA777A11-BD88-4E04-9BF5-173FB4C137A6")
    }
}
