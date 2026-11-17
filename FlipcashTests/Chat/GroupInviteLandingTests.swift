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
        landing(join: { _, _ in throw error })
    }

    private func landing(join: @escaping GroupInviteLanding.Service.Join) -> GroupInviteLanding {
        GroupInviteLanding(service: .init(
            owner: KeyPair.generate()!,
            getInvite: { _ in throw ErrorGetInvite.notFound },
            getRoster: { _, _ in throw ErrorGetRoster.denied },
            join: join,
            isMember: { _ in false }
        ))
    }

    @Test("BANNED from JoinChat shows the alert and pops the preview")
    func bannedPops() async {
        let result = await landing(joinThrows: .banned).join(secret, conversationID: conversationID, memberCount: 3)
        #expect(result == .banned)
        #expect(result.alert == .init(
            title: "You Can’t Join This Group",
            subtitle: "The host has removed you from this group",
            popsPreview: true
        ))
    }

    @Test("INVITE_NOT_FOUND from JoinChat shows the alert and pops the preview")
    func inviteNotFoundPops() async {
        let result = await landing(joinThrows: .inviteNotFound).join(secret, conversationID: conversationID, memberCount: 3)
        #expect(result == .notFound)
        #expect(result.alert == .init(
            title: "Link Not Found",
            subtitle: "This invite link isn’t valid. Ask whoever sent it for a new one",
            popsPreview: true
        ))
    }

    @Test("DENIED and a transport failure keep the preview")
    func otherFailuresStay() async {
        let denied = await landing(joinThrows: .denied).join(secret, conversationID: conversationID, memberCount: 3)
        #expect(denied.alert == .init(title: "Couldn’t Join Group", subtitle: "Something went wrong. Please try again", popsPreview: false))
        let transport = await landing(joinThrows: .transportFailure).join(secret, conversationID: conversationID, memberCount: 3)
        #expect(transport.alert == .init(title: "Couldn’t Join Group", subtitle: "Check your connection and try again", popsPreview: false))
    }

    @Test("A dead link or a gone group changes the screen instead of alerting")
    func stateChangesHaveNoAlert() async {
        #expect(await landing(joinThrows: .inviteExpired).join(secret, conversationID: conversationID, memberCount: 3).alert == nil)
        #expect(await landing(joinThrows: .notFound).join(secret, conversationID: conversationID, memberCount: 3).alert == nil)
    }

    // MARK: - Analytics -

    @Test("A join that goes through sends one Group: Joined with the member count passed in")
    func joinSendsGroupJoined() async throws {
        let landing = landing(join: { _, _ in })
        let sent = await Analytics.recordingSendsAsync {
            _ = await landing.join(secret, conversationID: conversationID, memberCount: 5)
        }
        let event = try sent.single
        #expect(event.name == "Group: Joined")
        #expect(event.properties["State"] as? String == "Success")
        #expect(event.properties["Error"] == nil)
        #expect(event.properties["Member Count"] as? Double == 5)
        #expect(event.properties["Gated"] as? Bool == false)
    }

    @Test("A refused join sends one Group: Joined with the member count passed in")
    func failedJoinSendsGroupJoined() async throws {
        let landing = landing(joinThrows: .banned)
        let sent = await Analytics.recordingSendsAsync {
            _ = await landing.join(secret, conversationID: conversationID, memberCount: 8)
        }
        let event = try sent.single
        #expect(event.name == "Group: Joined")
        #expect(event.properties["State"] as? String == "Failure")
        #expect(event.properties["Error"] as? String == "Banned")
        #expect(event.properties["Member Count"] as? Double == 8)
        #expect(event.properties["Gated"] as? Bool == false)
    }
}
