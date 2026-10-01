//
//  MentionSuggestionMappingTests.swift
//  FlipcashCoreTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Testing
import Foundation
import FlipcashAPI
@testable import FlipcashCore

@Suite("MentionSuggestion proto mapping")
struct MentionSuggestionMappingTests {

    @Test("Maps the profile, user id and last sent time")
    func mapsFields() throws {
        let userID = UUID()
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
        let proto = suggestion(userID: userID, username: "ted_1") {
            $0.lastSentAt = .init(date: sentAt)
        }

        let mapped = try #require(MentionSuggestion(proto))
        #expect(mapped.userID == userID)
        #expect(mapped.lastSentAt == sentAt)
        #expect(mapped.member.username?.value == "ted_1")
        #expect(mapped.member.displayName == "Ted")
        #expect(mapped.member.userID == userID)
    }

    @Test("A suggestion for another reason has no last sent time")
    func unsetLastSentAt() throws {
        let mapped = try #require(MentionSuggestion(suggestion(userID: UUID(), username: "ted_1")))
        #expect(mapped.lastSentAt == nil)
    }

    @Test("A suggestion without a username is dropped")
    func dropsWithoutUsername() {
        #expect(MentionSuggestion(suggestion(userID: UUID(), username: nil)) == nil)
    }

    @Test("A suggestion without a user id is dropped")
    func dropsWithoutUserID() {
        #expect(MentionSuggestion(suggestion(userID: nil, username: "ted_1")) == nil)
    }

    private func suggestion(
        userID: UUID?,
        username: String?,
        configure: (inout Flipcash_Chat_V1_MentionSuggestion) -> Void = { _ in }
    ) -> Flipcash_Chat_V1_MentionSuggestion {
        var proto = Flipcash_Chat_V1_MentionSuggestion.with {
            $0.userProfile = .with {
                $0.displayName = "Ted"
                if let userID { $0.userID = .with { $0.value = userID.data } }
                if let username { $0.username = .with { $0.value = username } }
            }
        }
        configure(&proto)
        return proto
    }
}
