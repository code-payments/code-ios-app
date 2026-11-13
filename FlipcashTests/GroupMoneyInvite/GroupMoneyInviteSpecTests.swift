//
//  GroupMoneyInviteSpecTests.swift
//  FlipcashTests
//
//  Phase 2 of the Group Money redesign: New Group, the group-ready state, the
//  Invite People sheet and the join preview, behind the same gate as the
//  phase 1 shell (`BetaFlags.showsGroupMoneyUI(isStaff:)`). Frames: New Group
//  (nodes 13729:462, 13729:552), group ready (13729:642, 13729:851), Invite
//  People (13729:672), join preview (13729:1404). Written from the brief and
//  the frames before the implementation: each item pins the shell-on outcome
//  and today's outcome with the shell off.
//

import Foundation
import SwiftUI
import Testing
import FlipcashCore
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("Group Money invite spec")
struct GroupMoneyInviteSpecTests {

    private static let groupID = ConversationID(data: Data(repeating: 7, count: 16))

    // MARK: - 1. The Groups tab's + -

    @Test("1.1 with the shell on, + opens New Group directly")
    func plus_opensNewGroup_shellOn() {
        #expect(ChatListComposeRoute.destination(showsGroupMoney: true) == .newPrivateGroup)
    }

    @Test("1.2 with the shell off, + opens the New Chat menu")
    func plus_opensNewChat_shellOff() {
        #expect(ChatListComposeRoute.destination(showsGroupMoney: false) == .newChat)
    }

    // MARK: - 2. New Group (13729:462, 13729:552) -

    @Test("2.1 the shell's New Group is titled New Group with a plain name placeholder")
    func newGroup_titleAndPlaceholder_shellOn() {
        let layout = NewGroupFormLayout(privacy: .private, showsGroupMoney: true)
        #expect(layout.title == "New Group")
        #expect(layout.namePlaceholder == "Group Name")
    }

    @Test("2.2 the shell's New Group has one card and no footnote or community sections")
    func newGroup_noFootnote_shellOn() {
        let layout = NewGroupFormLayout(privacy: .private, showsGroupMoney: true)
        #expect(layout.showsPrivacyFootnote == false)
        #expect(layout.showsCommunitySections == false)
    }

    @Test("2.3 with the shell off, the private form keeps its footnote and required placeholder")
    func newGroup_privateUnchanged_shellOff() {
        let layout = NewGroupFormLayout(privacy: .private, showsGroupMoney: false)
        #expect(layout.title == "New Group")
        #expect(layout.namePlaceholder == "Group Name (Required)")
        #expect(layout.showsPrivacyFootnote == true)
        #expect(layout.showsCommunitySections == false)
    }

    @Test("2.4 with the shell off, the community form keeps its title and sections")
    func newGroup_publicUnchanged_shellOff() {
        let layout = NewGroupFormLayout(privacy: .public, showsGroupMoney: false)
        #expect(layout.title == "New Community Chat")
        #expect(layout.namePlaceholder == "Group Name (Required)")
        #expect(layout.showsPrivacyFootnote == false)
        #expect(layout.showsCommunitySections == true)
    }

    @Test("2.5 Create is disabled with no name and enabled once a name is entered")
    func newGroup_createEnabledByName() {
        let model = NewPublicGroupModel(privacy: .private)
        let session = StubGateHoldings()
        #expect(model.canCreate(session: session, rates: [:]) == false)
        model.title = "   "
        #expect(model.canCreate(session: session, rates: [:]) == false)
        model.title = "Road Trip"
        #expect(model.canCreate(session: session, rates: [:]) == true)
    }

    @Test("2.6 the shell's Create pill is grey while disabled and blue once enabled")
    func newGroup_createPillColour_shellOn() {
        let layout = NewGroupFormLayout(privacy: .private, showsGroupMoney: true)
        #expect(layout.createPill(isEnabled: false) == .grey)
        #expect(layout.createPill(isEnabled: true) == .blue)
    }

    @Test("2.7 with the shell off, Create keeps today's prominent style")
    func newGroup_createPillUnchanged_shellOff() {
        let layout = NewGroupFormLayout(privacy: .private, showsGroupMoney: false)
        #expect(layout.createPill(isEnabled: false) == .prominent)
        #expect(layout.createPill(isEnabled: true) == .prominent)
    }

    // MARK: - 3. Group just created (13729:642, 13729:851) -

    @Test("3.1 with the shell on, the group-ready card is a centred empty state")
    func groupReady_emptyState_shellOn() {
        #expect(GroupReadyCard.style(showsGroupMoney: true) == .emptyState)
    }

    @Test("3.2 with the shell off, the group-ready card stays an incoming bubble")
    func groupReady_bubble_shellOff() {
        #expect(GroupReadyCard.style(showsGroupMoney: false) == .incomingBubble)
    }

    @Test("3.3 the empty state reads Your group is ready, with an Invite People button")
    func groupReady_emptyStateCopy() {
        let copy = ChatInviteCardCopy(style: .emptyState, groupName: "Road Trip")
        #expect(copy.title == "Your group is ready")
        #expect(copy.subtitle == "Invite people to join your group.")
        #expect(copy.button == "Invite People")
    }

    @Test("3.4 the bubble keeps today's copy")
    func groupReady_bubbleCopy() {
        let copy = ChatInviteCardCopy(style: .incomingBubble, groupName: "Road Trip")
        #expect(copy.title == "Your Group Is Ready")
        #expect(copy.subtitle == "Invite people to join Road Trip")
        #expect(copy.button == "Invite People")
    }

    @Test("3.5 the header counts a group of one as 1 person")
    func groupReady_headerCount() {
        #expect(ConversationRosterSummary(memberCount: 1, version: 1).peopleCount == "1 person")
        #expect(ConversationRosterSummary(memberCount: 3, version: 1).peopleCount == "3 people")
    }

    @Test("3.6 with the shell on, the composer's $ is a blue circle")
    func composer_cashBlue_shellOn() {
        #expect(ComposerCashButtonStyle(showsGroupMoney: true) == .blue)
    }

    @Test("3.7 with the shell off, the composer's $ keeps its glass")
    func composer_cashGlass_shellOff() {
        #expect(ComposerCashButtonStyle(showsGroupMoney: false) == .glass)
    }

    // MARK: - 4. Invite People sheet (13729:672) -

    @Test("4.1 with the shell on, the group-ready button opens the Invite People sheet, never the host's link card")
    func invite_groupReadyRoute_shellOn() {
        for canInvite in [true, false] {
            for isPrivate in [true, false] {
                #expect(InvitePeopleRoute.forGroupReady(showsGroupMoney: true, canInvite: canInvite, isPrivate: isPrivate) == .invitePeopleSheet)
            }
        }
    }

    @Test("4.2 with the shell off, the group-ready button keeps today's routes")
    func invite_groupReadyRoute_shellOff() {
        #expect(InvitePeopleRoute.forGroupReady(showsGroupMoney: false, canInvite: true, isPrivate: true) == .shareSheet)
        #expect(InvitePeopleRoute.forGroupReady(showsGroupMoney: false, canInvite: true, isPrivate: false) == .linkCard)
        #expect(InvitePeopleRoute.forGroupReady(showsGroupMoney: false, canInvite: false, isPrivate: false) == .shareSheet)
    }

    @Test("4.3 group info's Invite People opens the same sheet with the shell on, and today's card or share sheet with it off")
    func invite_groupInfoRoute() {
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: true, canInvite: true) == .invitePeopleSheet)
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: true, canInvite: false) == .invitePeopleSheet)
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: false, canInvite: true) == .linkCard)
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: false, canInvite: false) == .shareSheet)
    }

    @Test("4.4 the Invite People sheet presents through the router as the root sheet over a tab")
    func invite_presentsThroughRouter_root() {
        let router = AppRouter()
        router.presentInvitePeople(Self.groupID)
        #expect(router.presentedSheets == [.invitePeople(Self.groupID)])
    }

    @Test("4.5 the Invite People sheet stacks over a chat that is itself in a sheet")
    func invite_presentsThroughRouter_nested() {
        let router = AppRouter()
        router.present(.tips)
        router.presentInvitePeople(Self.groupID)
        #expect(router.presentedSheets == [.tips, .invitePeople(Self.groupID)])
    }

    @Test("4.6 the shell's sheet: close on the left, the group, the line, the caption and three square tiles")
    func invite_sheetLayout_shellOn() {
        let layout = GroupInviteSheetLayout(showsGroupMoney: true)
        #expect(layout.title == "Invite People")
        #expect(layout.closeEdge == .leading)
        #expect(layout.showsGroupIdentity == true)
        #expect(layout.message == "Send this link to the people you want in your group.")
        #expect(layout.linkCaption == "Anyone with the link can join.")
        #expect(layout.tileTitles == ["Copy Link", "Share Link", "QR Code"])
        #expect(layout.tilesAreSquare == true)
    }

    @Test("4.7 with the shell off, the group share sheet is unchanged")
    func invite_sheetLayout_shellOff() {
        let layout = GroupInviteSheetLayout(showsGroupMoney: false)
        #expect(layout.title == "Invite People")
        #expect(layout.closeEdge == .trailing)
        #expect(layout.showsGroupIdentity == false)
        #expect(layout.message == nil)
        #expect(layout.linkCaption == InviteLinkCopy.groupSheetLine)
        #expect(layout.tileTitles == ShareToChatsSheet.groupTileTitles)
        #expect(layout.tilesAreSquare == false)
    }

    // MARK: - 5. Join preview (13729:1404) -

    @Test("5.1 with the shell on, a live link's preview has no invited line")
    func join_noInvitedLine_shellOn() {
        #expect(GroupInvitePreview.note(dead: false, reason: nil, showsGroupMoney: true) == nil)
    }

    @Test("5.2 with the shell off, a live link's preview keeps the invited line")
    func join_invitedLine_shellOff() {
        #expect(GroupInvitePreview.note(dead: false, reason: nil, showsGroupMoney: false) == "Private group · You’ve been invited to join")
    }

    @Test("5.3 a dead link keeps its line either way, and an unknown reason gets none")
    func join_deadLine_bothWays() {
        for shell in [true, false] {
            #expect(GroupInvitePreview.note(dead: true, reason: .expired, showsGroupMoney: shell) == "This invite link has expired.")
            #expect(GroupInvitePreview.note(dead: true, reason: nil, showsGroupMoney: shell) == nil)
        }
    }

    @Test("5.4 the member heading is pluralised")
    func join_memberCountPluralised() {
        #expect(PrivateGroupCopy.memberCount(1) == "1 member")
        #expect(PrivateGroupCopy.memberCount(2) == "2 members")
    }

    @Test("5.5 the join button reads Join Group")
    func join_buttonTitle() {
        #expect(GroupInvitePreview.joinTitle == "Join Group")
    }
}
