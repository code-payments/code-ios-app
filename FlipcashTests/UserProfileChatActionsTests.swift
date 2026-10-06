//
//  UserProfileChatActionsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// How a person's profile behaves by the surface it was opened from.
@MainActor
@Suite("User profile chat actions")
struct UserProfileChatActionsTests {

    @Test(
        "Blocking from a link or a transaction returns to the screen the profile opened over",
        arguments: [UserProfileOrigin.deeplink, .transaction]
    )
    func openerOrigins_blockReturnsToOpener(_ origin: UserProfileOrigin) {
        #expect(origin.blockReturnsToOpener)
    }

    @Test(
        "Blocking from a chat-opened profile resets the stack, which can hold the blocked DM",
        arguments: [UserProfileOrigin.directMessage, .groupMember, .mention, .scan, .usernameLookup]
    )
    func chatOrigins_blockResetsStack(_ origin: UserProfileOrigin) {
        #expect(!origin.blockReturnsToOpener)
    }

    @Test("A link, a scan, and a username search arrive already fetched; the rest fetch")
    func arrivesFetched_onlyAfterALookup() {
        #expect(UserProfileOrigin.deeplink.arrivesFetched)
        #expect(UserProfileOrigin.scan.arrivesFetched)
        #expect(UserProfileOrigin.usernameLookup.arrivesFetched)
        #expect(!UserProfileOrigin.directMessage.arrivesFetched)
        #expect(!UserProfileOrigin.groupMember.arrivesFetched)
        #expect(!UserProfileOrigin.mention.arrivesFetched)
        #expect(!UserProfileOrigin.transaction.arrivesFetched)
    }

    @Test("Open Chat returns to the DM only when the profile was opened from that DM")
    func openChat_returnsToDMOnlyFromDirectMessage() {
        #expect(UserProfileOrigin.directMessage.returnsToExistingDM)
        #expect(!UserProfileOrigin.groupMember.returnsToExistingDM)
        #expect(!UserProfileOrigin.mention.returnsToExistingDM)
        #expect(!UserProfileOrigin.deeplink.returnsToExistingDM)
        #expect(!UserProfileOrigin.scan.returnsToExistingDM)
        #expect(!UserProfileOrigin.usernameLookup.returnsToExistingDM)
        #expect(!UserProfileOrigin.transaction.returnsToExistingDM)
    }

    // MARK: - Destinations -

    @Test("The origin is part of the profile destination's identity but not its log keys")
    func userProfile_originDistinguishesButDoesNotLog() {
        let userID = UUID()
        let fromDM = AppRouter.Destination.userProfile(userID, origin: .directMessage)
        let fromGroup = AppRouter.Destination.userProfile(userID, origin: .groupMember)
        #expect(fromDM != fromGroup)
        #expect(fromDM.description == "userProfile")
        #expect(fromGroup.description == "userProfile")
        #expect(fromDM.payload == userID.uuidString)
        #expect(fromDM.owningStack == .tips)
    }
}
