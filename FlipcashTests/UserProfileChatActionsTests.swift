//
//  UserProfileChatActionsTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

/// A person's profile offers Message and Send Cash into the DM with them, except where that would
/// lead back to where the viewer came from or point at themselves.
@MainActor
@Suite("User profile chat actions")
struct UserProfileChatActionsTests {

    // MARK: - Visibility -

    @Test("A group member's profile offers the chat actions")
    func groupMember_showsChatActions() {
        #expect(UserProfileOrigin.groupMember.showsChatActions(profileUserID: UUID(), selfUserID: UUID()))
    }

    @Test("A profile opened from the DM with that person hides the chat actions")
    func directMessage_hidesChatActions() {
        #expect(!UserProfileOrigin.directMessage.showsChatActions(profileUserID: UUID(), selfUserID: UUID()))
    }

    @Test(
        "The viewer's own profile hides the chat actions from either origin",
        arguments: [UserProfileOrigin.groupMember, .directMessage]
    )
    func ownProfile_hidesChatActions(_ origin: UserProfileOrigin) {
        let me = UUID()
        #expect(!origin.showsChatActions(profileUserID: me, selfUserID: me))
    }

    @Test("Only a profile opened from the DM offers muting it")
    func mute_showsOnlyFromDirectMessage() {
        #expect(UserProfileOrigin.directMessage.showsMute)
        #expect(!UserProfileOrigin.groupMember.showsMute)
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
