//
//  GroupReadyCardTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Group-ready card")
struct GroupReadyCardTests {

    @Test("Roster not resolved: no card")
    func rosterUnresolved() {
        #expect(!GroupReadyCard.isShown(isGroup: true, memberCount: nil, viewerCanInvite: true))
        #expect(!GroupReadyCard.isShown(isGroup: true, memberCount: 0, viewerCanInvite: true))
    }

    @Test("Alone and may invite: card")
    func aloneCanInvite() {
        #expect(GroupReadyCard.isShown(isGroup: true, memberCount: 1, viewerCanInvite: true))
    }

    @Test("Alone without can_invite: no card")
    func aloneCannotInvite() {
        #expect(!GroupReadyCard.isShown(isGroup: true, memberCount: 1, viewerCanInvite: false))
    }

    @Test("Someone else joined: no card")
    func joined() {
        #expect(!GroupReadyCard.isShown(isGroup: true, memberCount: 2, viewerCanInvite: true))
    }

    @Test("Not a group: no card")
    func notGroup() {
        #expect(!GroupReadyCard.isShown(isGroup: false, memberCount: 1, viewerCanInvite: true))
    }

    @Test("Reads the conversation's roster, type and viewer state")
    func fromConversation() {
        func group(count: UInt64, canInvite: Bool, isPrivate: Bool = true) -> Conversation {
            Conversation(
                id: ConversationID(data: Data(repeating: 1, count: 16)),
                members: [],
                lastMessage: nil,
                lastActivity: .now,
                type: .group,
                rosterSummary: ConversationRosterSummary(memberCount: count, version: 1),
                viewerState: ConversationViewerState(mute: nil, canEdit: true, canInvite: canInvite),
                isPrivate: isPrivate
            )
        }
        #expect(GroupReadyCard.isShown(group(count: 1, canInvite: true)))
        #expect(!GroupReadyCard.isShown(group(count: 2, canInvite: true)))
        #expect(!GroupReadyCard.isShown(group(count: 1, canInvite: false)))
        // A public group's link is shareable by any member, and its host holds no can-invite.
        #expect(GroupReadyCard.isShown(group(count: 1, canInvite: false, isPrivate: false)))
        #expect(!GroupReadyCard.isShown(nil))
    }

    @Test("Empty chat-list preview follows the card predicate")
    func emptyPreview() {
        func chat(type: ConversationType = .group, count: UInt64, canInvite: Bool, isPrivate: Bool) -> Conversation {
            Conversation(
                id: ConversationID(data: Data(repeating: 2, count: 16)),
                members: [],
                lastMessage: nil,
                lastActivity: .now,
                type: type,
                rosterSummary: ConversationRosterSummary(memberCount: count, version: 1),
                viewerState: ConversationViewerState(mute: nil, canEdit: true, canInvite: canInvite),
                isPrivate: isPrivate
            )
        }
        let invite = String(localized: "Invite people to get started")
        let nothing = String(localized: "Nothing yet")
        // Alone, private, may invite; alone, public without can-invite.
        #expect(GroupReadyCard.emptyPreview(for: chat(count: 1, canInvite: true, isPrivate: true)) == invite)
        #expect(GroupReadyCard.emptyPreview(for: chat(count: 1, canInvite: false, isPrivate: false)) == invite)
        // Alone, private, may not invite: nothing to offer.
        #expect(GroupReadyCard.emptyPreview(for: chat(count: 1, canInvite: false, isPrivate: true)) == nothing)
        // Roster unresolved or someone else in.
        #expect(GroupReadyCard.emptyPreview(for: chat(count: 0, canInvite: true, isPrivate: false)) == nothing)
        #expect(GroupReadyCard.emptyPreview(for: chat(count: 2, canInvite: true, isPrivate: false)) == nothing)
        // A DM never gets the invitation.
        #expect(GroupReadyCard.emptyPreview(for: chat(type: .contactDm, count: 1, canInvite: true, isPrivate: false)) == nothing)
    }
}
