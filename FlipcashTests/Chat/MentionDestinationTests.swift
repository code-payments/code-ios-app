//
//  MentionDestinationTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// Where a tapped `@handle` lands once its lookup answers.
@Suite struct MentionDestinationTests {

    private static let otherID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private static let counterpartID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private struct Offline: Error {}

    private static func facts(_ userID: UserID, isOwn: Bool = false) -> Result<UserLinkFacts, any Error> {
        let profile = Profile(
            displayName: "Satoshi",
            phone: Optional<Phone>.none,
            email: nil,
            joinedAt: nil,
            userID: userID,
            username: Username("satoshi"),
            minDmChatInitFee: nil
        )
        return .success(UserLinkFacts(profile: profile, userID: userID, isOwn: isOwn))
    }

    @Test func someoneElseOpensTheirProfileWithChatActions() {
        let destination = MentionDestination.destination(for: Self.facts(Self.otherID), counterpart: Self.counterpartID)
        #expect(destination == .profile(Self.otherID, origin: .mention))
    }

    @Test func theDMCounterpartOpensTheWayTheTitleDoes() {
        let destination = MentionDestination.destination(for: Self.facts(Self.counterpartID), counterpart: Self.counterpartID)
        #expect(destination == .profile(Self.counterpartID, origin: .directMessage))
    }

    @Test func theViewersOwnHandleOpensTheirTipCard() {
        let destination = MentionDestination.destination(for: Self.facts(Self.otherID, isOwn: true), counterpart: nil)
        #expect(destination == .ownTipCard)
    }

    @Test func anUnclaimedHandleIsNoSuchAccount() {
        #expect(MentionDestination.destination(for: .failure(NoSuchAccount()), counterpart: nil) == .noSuchAccount)
        #expect(MentionDestination.destination(for: .failure(ErrorFetchProfile.notFound), counterpart: nil) == .noSuchAccount)
    }

    @Test func aFailedLookupIsNotReadAsUnclaimed() {
        #expect(MentionDestination.destination(for: .failure(Offline()), counterpart: nil) == .lookupFailed)
    }

    @Test func aMentionOffersChatActionsButNotMute() {
        #expect(UserProfileOrigin.mention.showsChatActions(profileUserID: Self.otherID, selfUserID: Self.counterpartID))
        #expect(!UserProfileOrigin.mention.showsMute)
    }
}
