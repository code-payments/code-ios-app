//
//  GroupInviteLandingTests.swift
//  FlipcashTests
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Joining a group through an invite link")
struct GroupInviteLandingTests {

    private let conversationID = ConversationID(data: Data(repeating: 7, count: 32))
    private let secret = InviteLinkSecret(data: Data(repeating: 9, count: 32))

    private func landing(joinThrows error: ErrorJoinChat) -> GroupInviteLanding {
        GroupInviteLanding(service: .init(
            owner: KeyPair.generate()!,
            getInvite: { _ in throw ErrorGetInvite.notFound },
            getRoster: { _, _ in throw ErrorGetRoster.denied },
            join: { _, _ in throw error },
            isMember: { _ in false }
        ))
    }

    @Test("BANNED from JoinChat shows the alert and pops the preview")
    func bannedPops() async {
        let result = await landing(joinThrows: .banned).join(secret, conversationID: conversationID)
        #expect(result == .banned)
        #expect(result.alert == .init(
            title: "You Can’t Join This Group",
            subtitle: "The host has removed you from this group",
            popsPreview: true
        ))
    }

    @Test("INVITE_NOT_FOUND from JoinChat shows the alert and pops the preview")
    func inviteNotFoundPops() async {
        let result = await landing(joinThrows: .inviteNotFound).join(secret, conversationID: conversationID)
        #expect(result == .notFound)
        #expect(result.alert == .init(
            title: "Link Not Found",
            subtitle: "This invite link isn’t valid. Ask whoever sent it for a new one",
            popsPreview: true
        ))
    }

    @Test("DENIED and a transport failure keep the preview")
    func otherFailuresStay() async {
        let denied = await landing(joinThrows: .denied).join(secret, conversationID: conversationID)
        #expect(denied.alert == .init(title: "Couldn’t Join Group", subtitle: "Something went wrong. Please try again", popsPreview: false))
        let transport = await landing(joinThrows: .transportFailure).join(secret, conversationID: conversationID)
        #expect(transport.alert == .init(title: "Couldn’t Join Group", subtitle: "Check your connection and try again", popsPreview: false))
    }

    @Test("A dead link or a gone group changes the screen instead of alerting")
    func stateChangesHaveNoAlert() async {
        #expect(await landing(joinThrows: .inviteExpired).join(secret, conversationID: conversationID).alert == nil)
        #expect(await landing(joinThrows: .notFound).join(secret, conversationID: conversationID).alert == nil)
    }
}
