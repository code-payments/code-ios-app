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

    @Test("Blocking from a link-opened profile returns to where the link was followed")
    func deeplink_blockReturnsToOpener() {
        #expect(UserProfileOrigin.deeplink.blockReturnsToOpener)
    }

    @Test(
        "Blocking from a chat-opened profile resets the stack, which can hold the blocked DM",
        arguments: [UserProfileOrigin.directMessage, .groupMember, .mention]
    )
    func chatOrigins_blockResetsStack(_ origin: UserProfileOrigin) {
        #expect(!origin.blockReturnsToOpener)
    }

    @Test("Only a link-opened profile arrives already fetched")
    func arrivesFetched_onlyFromDeeplink() {
        #expect(UserProfileOrigin.deeplink.arrivesFetched)
        #expect(!UserProfileOrigin.directMessage.arrivesFetched)
        #expect(!UserProfileOrigin.groupMember.arrivesFetched)
        #expect(!UserProfileOrigin.mention.arrivesFetched)
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

    @Test("Send Cash's chat destination logs apart from the plain chat, keyed by the counterpart")
    func sendingCash_destination() {
        let userID = UUID()
        let destination = AppRouter.Destination.tipConversationForUserSendingCash(userID)
        #expect(destination.description == "tipConversationForUserSendingCash")
        #expect(destination.payload == userID.uuidString)
        #expect(destination.owningStack == .tips)
        #expect(destination != .tipConversationForUser(userID))
    }
}
