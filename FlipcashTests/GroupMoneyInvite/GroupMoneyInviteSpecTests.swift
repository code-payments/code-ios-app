//
//  GroupMoneyInviteSpecTests.swift
//  FlipcashTests
//
//  Phase 2 of the Group Money redesign: New Group, the group-ready state, the
//  Invite People sheet and the join preview, behind the same gate as the
//  phase 1 shell (`BetaFlags.showsGroupMoneyUI(isStaff:)`). Frames: New Group
//  (nodes 13729:462, 13729:552), group ready (13729:642, 13729:851), join
//  preview (13729:1404). Written from the brief and the frames before the
//  implementation: each item pins the shell-on outcome and today's outcome with
//  the shell off. Invite People's frame (13729:672) is not built: the shell's
//  Invite People opens the share sheet Manage Invites' Share Link opens.
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

    // MARK: - 4. Invite People sheet -

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

    @Test("4.3 group info's Invite People opens today's card or share sheet, with the shell on or off")
    func invite_groupInfoRoute() {
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: true, canInvite: true) == .linkCard)
        #expect(InvitePeopleRoute.forGroupInfo(showsGroupMoney: true, canInvite: false) == .shareSheet)
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

    @Test("4.9 with the shell on, group info's Invite People is today's, never the router's sheet that makes a link as it opens")
    func invite_groupInfoKeepsTodaysSheet_shellOn() {
        for canInvite in [true, false] {
            let route = InvitePeopleRoute.forGroupInfo(showsGroupMoney: true, canInvite: canInvite)
            #expect(route != .invitePeopleSheet)
            #expect(route == InvitePeopleRoute.forGroupInfo(showsGroupMoney: false, canInvite: canInvite))
        }
    }

    @Test("4.10 with the shell on, the router's Invite People sheet opens at its content's height, not full height")
    func invite_routerSheetFitsContent_shellOn() async throws {
        let flags = BetaFlags()
        let wasOn = flags.hasEnabled(.groupMoneyUI)
        let hadAccess = flags.accessGranted
        flags.set(.groupMoneyUI, enabled: true)
        flags.setAccessGranted(true)
        defer {
            flags.set(.groupMoneyUI, enabled: wasOn)
            flags.setAccessGranted(hadAccess)
        }

        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        let view = Color.clear
            .modifier(RootSheetHostModifier())
            .environment(flags)
            .injectingEnvironment(from: sessionContainer)
            .injectingEnvironment(from: Container.mock)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer {
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
        }

        sessionContainer.appRouter.presentInvitePeople(Self.groupID)

        // The sheet opens on `.large` until it has measured its content, then takes that height.
        try await waitUntil {
            window.layoutIfNeeded()
            guard let sheet = window.rootViewController?.presentedViewController?.sheetPresentationController else { return false }
            let detents = sheet.detents.map(\.identifier)
            return !detents.isEmpty && !detents.contains(.large)
        }
        let presented = try #require(window.rootViewController?.presentedViewController)
        try await waitUntil {
            window.layoutIfNeeded()
            let height = presented.view.frame.height
            return height > 0 && height < window.bounds.height - 100
        }
    }

    @Test("4.11 with the shell on, the chat's Invite People opens the sheet Manage Invites' Share Link opens")
    func invite_chatSheetIsManageInvitesSheet_shellOn() async throws {
        let flags = BetaFlags()
        let wasOn = flags.hasEnabled(.groupMoneyUI)
        let hadAccess = flags.accessGranted
        flags.set(.groupMoneyUI, enabled: true)
        flags.setAccessGranted(true)
        defer {
            flags.set(.groupMoneyUI, enabled: wasOn)
            flags.setAccessGranted(hadAccess)
        }

        // A titled group the viewer can't invite to, so the chat's sheet shares the plain link and
        // never asks the server for an invite link.
        let groupName = "Kestrel Supper Club"
        let sessionContainer = try SessionContainer.makeTest(holdings: [])
        try sessionContainer.database.upsertConversation(
            Conversation(id: Self.groupID, members: [], lastMessage: nil, lastActivity: .now, type: .group, title: groupName)
        )
        await sessionContainer.conversationController.hydrateFromDatabase()

        // The chat's Invite People, presented through the router as the group-ready card does.
        let chat = try await Self.settledSheet(
            Color.clear.modifier(RootSheetHostModifier()),
            link: .groupChatInvite(for: Self.groupID),
            sessionContainer: sessionContainer,
            flags: flags
        ) {
            sessionContainer.appRouter.presentInvitePeople(Self.groupID)
        }
        sessionContainer.appRouter.dismissSheet()

        // Manage Invites' Share Link on the group's one active link, built by Manage Invites itself.
        let links = GroupInviteLinks(conversationID: Self.groupID, service: Self.oneLinkService())
        try await links.load()
        let entry = try #require(links.active.first)
        let url = try #require(entry.url)
        let manage = try await Self.settledSheet(
            Color.clear.sheet(isPresented: .constant(true)) {
                InviteLinksScreen.shareSheet(Self.groupID, links: links, entry: entry.id, isPresented: .constant(true))
            },
            link: url,
            sessionContainer: sessionContainer,
            flags: flags
        )

        #expect(chat == manage)
        // The group's avatar reads as the group's name too, so no label naming the group means
        // neither the avatar nor the name is drawn.
        #expect(!chat.contains { $0.label.contains(groupName) }, "sheet: \(chat)")
    }

    /// One element of a presented sheet: its accessibility label and its frame in the sheet.
    private struct SheetElement: Equatable, CustomStringConvertible {
        let label: String
        let frame: CGRect
        var description: String { "\(label) \(frame)" }
    }

    /// Hosts `root` in its own window, runs `present`, and reads the sheet it presents once the
    /// sheet has fitted its content and stopped moving. The sheet's own link reads as "<link>", so
    /// two sheets on different links compare equal when everything else is.
    private static func settledSheet(
        _ root: some View,
        link: URL,
        sessionContainer: SessionContainer,
        flags: BetaFlags,
        present: () -> Void = {}
    ) async throws -> [SheetElement] {
        let view = root
            .environment(flags)
            .injectingEnvironment(from: sessionContainer)
            .injectingEnvironment(from: Container.mock)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        defer {
            window.rootViewController?.dismiss(animated: false)
            window.isHidden = true
        }
        present()

        let shownLink = InviteLinkPanel.display(link)
        var last: [SheetElement] = []
        var stableReads = 0
        // Title and QR Code are drawn by every group sheet, so a sheet that differs fails the
        // comparison rather than this wait.
        try await waitUntil {
            window.layoutIfNeeded()
            guard let presented = window.rootViewController?.presentedViewController,
                  let sheet = presented.sheetPresentationController,
                  !sheet.detents.isEmpty,
                  !sheet.detents.map(\.identifier).contains(.large) else { return false }
            let elements = Self.elements(in: presented.view, link: shownLink)
            let labels = elements.map(\.label)
            guard labels.contains("Invite People"), labels.contains("QR Code") else { return false }
            stableReads = elements == last ? stableReads + 1 : 0
            last = elements
            return stableReads >= 20
        }
        return last
    }

    /// Every accessibility element on screen in `view`, in reading order, with `link` as "<link>".
    private static func elements(in view: UIView, link: String) -> [SheetElement] {
        func walk(_ object: NSObject, depth: Int) -> [SheetElement] {
            guard depth < 40 else { return [] }
            if let view = object as? UIView, view.isHidden || view.alpha <= 0.01 { return [] }
            var found: [SheetElement] = []
            if object.isAccessibilityElement, let label = object.accessibilityLabel {
                let screen = view.window?.windowScene?.screen.coordinateSpace
                let frame = screen.map { view.convert(object.accessibilityFrame, from: $0) } ?? object.accessibilityFrame
                found.append(SheetElement(
                    label: label == link ? "<link>" : label,
                    frame: CGRect(x: frame.minX.rounded(), y: frame.minY.rounded(), width: frame.width.rounded(), height: frame.height.rounded())
                ))
            }
            for case let element as NSObject in object.accessibilityElements ?? [] {
                found += walk(element, depth: depth + 1)
            }
            if let view = object as? UIView {
                for subview in view.subviews { found += walk(subview, depth: depth + 1) }
            }
            return found
        }
        return walk(view, depth: 0)
    }

    /// A server with one active, never-expiring invite link the viewer made.
    private static func oneLinkService() -> GroupInviteLinks.Service {
        let viewer = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
        let invite = Invite(
            id: InviteID(data: Data(repeating: 9, count: 16)),
            conversationID: groupID,
            createdBy: viewer,
            maxUses: 0,
            useCount: 0,
            createdAt: .now,
            expiresAt: nil,
            status: .active,
            secretEnvelope: InviteSecretEnvelope(scheme: 1, nonce: Data([9]), ciphertext: Data([9]))
        )
        return GroupInviteLinks.Service(
            selfUserID: viewer,
            list: { _ in [invite] },
            create: { _, _, _, _ in throw UnexpectedCreate() },
            revoke: { _, _ in },
            secret: { $0.id.data },
            link: { secret in URL(string: "https://app.flipcash.com/chat/invite#s=\(secret.base64EncodedString())") },
            newSecret: { Data(repeating: 1, count: 32) }
        )
    }

    private struct UnexpectedCreate: Error {}

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
