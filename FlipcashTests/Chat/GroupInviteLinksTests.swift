//
//  GroupInviteLinksTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("A hosted group's invite links")
struct GroupInviteLinksTests {

    private let group = ConversationID.test(1)
    private let me = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A server fake: records each create's secret and answers with a queued result.
    @MainActor
    final class Server {
        var invites: [Invite] = []
        var createResults: [Result<Invite.Status, ErrorCreateInvite>] = []
        var createdSecrets: [Data] = []
        var createdExpiries: [Date?] = []
        var createdMaxUses: [UInt32] = []
        var listError: Error?
        var revoked: [InviteID] = []
        var secretCounter: UInt8 = 0
        /// While true, a create waits before answering, so a test can ask again mid-flight.
        var holdCreate = false
    }

    private func invite(_ id: UInt8, status: Invite.Status = .active, createdBy: UserID? = nil, daysAgo: Double = 0, expiresAt: Date? = nil) -> Invite {
        Invite(
            id: InviteID(data: Data(repeating: id, count: 16)),
            conversationID: group,
            createdBy: createdBy ?? me,
            maxUses: 0,
            useCount: 0,
            createdAt: now.addingTimeInterval(-daysAgo * 86_400),
            expiresAt: expiresAt,
            status: status,
            secretEnvelope: InviteSecretEnvelope(scheme: 1, nonce: Data([id]), ciphertext: Data([id]))
        )
    }

    private func makeService(_ server: Server, unopenable: Set<InviteID> = []) -> GroupInviteLinks.Service {
        GroupInviteLinks.Service(
            selfUserID: me,
            list: { _ in
                if let error = server.listError { throw error }
                return server.invites
            },
            create: { _, secret, maxUses, expiresAt in
                server.createdSecrets.append(secret)
                while server.holdCreate { await Task.yield() }
                server.createdMaxUses.append(maxUses)
                server.createdExpiries.append(expiresAt)
                let status = try server.createResults.removeFirst().get()
                return Invite(
                    id: InviteID(data: secret.prefix(16)),
                    conversationID: group,
                    createdBy: me,
                    maxUses: maxUses,
                    useCount: 0,
                    createdAt: now,
                    expiresAt: expiresAt,
                    status: status,
                    secretEnvelope: nil
                )
            },
            revoke: { _, id in server.revoked.append(id) },
            secret: { invite in unopenable.contains(invite.id) ? nil : invite.id.data },
            link: { secret in URL(string: "https://app.flipcash.com/chat/invite#s=\(secret.first ?? 0)") },
            newSecret: {
                server.secretCounter += 1
                return Data(repeating: server.secretCounter, count: 32)
            }
        )
    }

    private func makeLinks(_ server: Server, unopenable: Set<InviteID> = []) -> GroupInviteLinks {
        GroupInviteLinks(conversationID: group, service: makeService(server, unopenable: unopenable), now: { now })
    }

    @Test("Current is the newest active link the viewer made whose secret opens here")
    func currentIsNewestOpenableOwn() async throws {
        let server = Server()
        server.invites = [
            invite(1, daysAgo: 5),
            invite(2, daysAgo: 1),
            invite(3, createdBy: UUID(), daysAgo: 0),
            invite(4, status: .revoked, daysAgo: 0.1),
            invite(5, daysAgo: 0.5),
        ]
        let links = makeLinks(server, unopenable: [InviteID(data: Data(repeating: 5, count: 16))])
        try await links.load()

        #expect(links.current?.id == InviteID(data: Data(repeating: 2, count: 16)))
        #expect(links.entries.map(\.id.data.first) == [3, 4, 5, 2, 1])
    }

    @Test("Inactive links more than 30 days past their end are hidden")
    func inactiveRetention() async throws {
        let server = Server()
        server.invites = [
            invite(1, status: .expired, daysAgo: 60, expiresAt: now.addingTimeInterval(-10 * 86_400)),
            invite(2, status: .expired, daysAgo: 60, expiresAt: now.addingTimeInterval(-40 * 86_400)),
            invite(3, status: .revoked, daysAgo: 31),
            invite(4, status: .exhausted, daysAgo: 2),
        ]
        let links = makeLinks(server)
        try await links.load()

        #expect(links.active.isEmpty)
        #expect(links.inactive.map(\.id.data.first) == [4, 1])
    }

    @Test("With no active link, the first share makes one that never expires, with no use limit")
    func firstShareCreates() async throws {
        let server = Server()
        server.createResults = [.success(.active)]
        let links = makeLinks(server)

        let url = try await links.currentLink()

        #expect(server.createdSecrets.count == 1)
        #expect(server.createdMaxUses == [0])
        #expect(server.createdExpiries == [nil])
        #expect(links.current?.url == url)
    }

    @Test("An existing current link is shared without a create")
    func existingLinkSkipsCreate() async throws {
        let server = Server()
        server.invites = [invite(1)]
        let links = makeLinks(server)

        _ = try await links.currentLink()

        #expect(server.createdSecrets.isEmpty)
    }

    @Test("A retry after a transport failure reuses the secret")
    func retryReusesSecret() async throws {
        let server = Server()
        server.createResults = [.failure(.transportFailure), .success(.active)]
        let links = makeLinks(server)

        await #expect(throws: ErrorCreateInvite.transportFailure) { try await links.currentLink() }
        _ = try await links.currentLink()

        #expect(server.createdSecrets.count == 2)
        #expect(server.createdSecrets[0] == server.createdSecrets[1])
    }

    @Test("A server refusal drops the secret, so the next attempt makes a new one")
    func refusalDropsSecret() async throws {
        let server = Server()
        server.createResults = [.failure(.tooManyInvites), .success(.active)]
        let links = makeLinks(server)

        await #expect(throws: ErrorCreateInvite.tooManyInvites) {
            try await links.create(expiry: .oneDay, limit: .ten)
        }
        try await links.create(expiry: .oneDay, limit: .ten)

        #expect(server.createdSecrets[0] != server.createdSecrets[1])
        #expect(server.createdMaxUses == [10, 10])
    }

    @Test("DENIED on create is thrown for the sheet's 1e")
    func deniedThrows() async {
        let server = Server()
        server.createResults = [.failure(.denied)]
        let links = makeLinks(server)

        await #expect(throws: ErrorCreateInvite.denied) { try await links.currentLink() }
        #expect(links.current == nil)
        #expect(server.createdSecrets.count == 1, "DENIED is not retried")
    }

    @Test("After DENIED the next attempt seals a new secret")
    func deniedDropsSecret() async throws {
        let server = Server()
        server.createResults = [.failure(.denied), .success(.active)]
        let links = makeLinks(server)

        await #expect(throws: ErrorCreateInvite.denied) { try await links.currentLink() }
        _ = try await links.currentLink()

        #expect(server.createdSecrets.count == 2)
        #expect(server.createdSecrets[0] != server.createdSecrets[1])
    }

    @Test("DENIED maps to 1e, which offers the group link")
    @MainActor
    func deniedShows1e() {
        var sharedGroupLink = false
        let item = InviteLinkDialogs.createFailed(ErrorCreateInvite.denied, onManage: {}, onShareGroupLink: { sharedGroupLink = true })

        #expect(item.title == "Invite Links Aren’t Available Yet")
        #expect(item.actions.map(\.title) == ["Share Group Link", "Cancel"])
        item.actions.first?.action()
        #expect(sharedGroupLink)
    }

    @Test("1e on the link card shares the plain link once and leaves Approve New Members off")
    @MainActor
    func deniedOnCardLeavesApproveOff() {
        let suite = "approve-1e-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let conversation = ConversationID(data: Data(repeating: 3, count: 16))
        let approve = ApproveNewMembers(defaults: defaults, owner: KeyPair.generate()!.publicKey)

        var shared: [InviteCardLink] = []
        let item = InviteLinkDialogs.cardCreateFailed(ErrorCreateInvite.denied, onManage: {}, onShare: { shared.append($0) })
        item.actions.first { $0.title == "Share Group Link" }?.action()

        #expect(shared == [.plain])
        #expect(!approve.isOn(for: conversation))
    }

    @Test("An OK that isn't active is not used as a link")
    func inactiveCreateRejected() async {
        let server = Server()
        server.createResults = [.success(.revoked), .success(.revoked)]
        let links = makeLinks(server)

        await #expect(throws: GroupInviteLinks.CreatedUnusable.self) { try await links.currentLink() }
        #expect(links.current == nil)
    }

    @Test("An OK that isn't active starts over once with a new secret")
    func inactiveCreateRestarts() async throws {
        let server = Server()
        server.createResults = [.success(.revoked), .success(.active)]
        let links = makeLinks(server)

        _ = try await links.currentLink()

        #expect(server.createdSecrets.count == 2)
        #expect(server.createdSecrets[0] != server.createdSecrets[1])
        #expect(links.current != nil)
    }

    @Test("2d offers the spec's use limits in order")
    func useLimitPresets() {
        #expect(GroupInviteLinks.UseLimit.allCases.map(\.maxUses) == [1, 5, 10, 25, 0])
    }

    @Test("A new link from 2d becomes current; Never sends no expiry")
    func newLinkBecomesCurrent() async throws {
        let server = Server()
        server.invites = [invite(9, daysAgo: 3)]
        server.createResults = [.success(.active)]
        let links = makeLinks(server)
        try await links.load()

        let entry = try await links.create(expiry: .never, limit: .unlimited)

        #expect(links.current?.id == entry.id)
        #expect(server.createdExpiries == [nil])
    }

    @Test("Revoking moves a link to Inactive")
    func revokeMovesToInactive() async throws {
        let server = Server()
        server.invites = [invite(1)]
        let links = makeLinks(server)
        try await links.load()

        try await links.revoke(links.active[0])

        #expect(server.revoked == [InviteID(data: Data(repeating: 1, count: 16))])
        #expect(links.active.isEmpty)
        #expect(links.inactive.count == 1)
        #expect(links.current == nil)
    }

    @Test("DENIED on load is thrown so the screen can pop")
    func loadDenied() async {
        let server = Server()
        server.listError = ErrorGetChatInvites.denied
        let links = makeLinks(server)

        await #expect(throws: ErrorGetChatInvites.denied) { try await links.load() }
        #expect(links.loadState == .failed)
    }

    @Test("The invite link's share sheet has a group card, as the plain link's does")
    func inviteSheetHasGroupCard() {
        let links = makeLinks(Server())
        #expect(ShareToChatsSheet.showsGroupCardTile(for: .inviteLink(group, links)))
        #expect(ShareToChatsSheet.showsGroupCardTile(for: .group(group)))
    }

    @Test("Both group sheets drop Recent Chats and order their tiles Copy, Share, QR Code")
    func groupSheetLayout() {
        let links = makeLinks(Server())
        for subject in [ShareToChatsSubject.inviteLink(group, links), .group(group)] {
            #expect(ShareToChatsSheet.isGroupSheet(subject))
            #expect(!ShareToChatsSheet.showsRecentChats(for: subject))
        }
        #expect(ShareToChatsSheet.groupTileTitles == ["Copy", "Share", "QR Code"])
        #expect(InviteLinkCopy.groupSheetLine == "Send this link to the people you want to join your group")
    }

    @Test("The shell's Invite People sheet fits its content, as today's does")
    func groupSheetHeight() {
        #expect(!GroupInviteSheetLayout(showsGroupMoney: true).opensFullHeight)
        #expect(!GroupInviteSheetLayout(showsGroupMoney: false).opensFullHeight)
    }

    @Test("Only the router's Invite People sheet takes the shell's layout; other group sheets keep today's")
    func shellLayoutIsInvitePeopleOnly() {
        let links = makeLinks(Server())
        for subject in [ShareToChatsSubject.inviteLink(group, links), .group(group)] {
            #expect(ShareToChatsSheet.layout(for: subject, isInvitePeople: true, showsGroupMoney: true).showsGroupMoney)
            #expect(!ShareToChatsSheet.layout(for: subject, isInvitePeople: false, showsGroupMoney: true).showsGroupMoney)
            #expect(!ShareToChatsSheet.layout(for: subject, isInvitePeople: true, showsGroupMoney: false).showsGroupMoney)
        }
        let url = URL(string: "https://app.flipcash.com/chat/x")!
        #expect(!ShareToChatsSheet.layout(for: .message(url), isInvitePeople: true, showsGroupMoney: true).showsGroupMoney)
    }

    @Test("The shell's caption promises open entry only for an invite link; the plain link asks the host and has none")
    func shellCaptionFollowsLink() {
        let links = makeLinks(Server())
        let invite = ShareToChatsSheet.layout(for: .inviteLink(group, links), isInvitePeople: true, showsGroupMoney: true)
        let plain = ShareToChatsSheet.layout(for: .group(group), isInvitePeople: true, showsGroupMoney: true)
        #expect(invite.linkCaption == "Anyone with the link can join.")
        #expect(plain.linkCaption == nil)
        #expect(ShareToChatsSheet.layout(for: .group(group), isInvitePeople: true, showsGroupMoney: false).linkCaption == InviteLinkCopy.groupSheetLine)
    }

    @Test("Profile, message and currency sheets keep Recent Chats")
    func otherSheetsKeepRecentChats() {
        let url = URL(string: "https://app.flipcash.com/chat/x")!
        for subject in [
            ShareToChatsSubject.user(userID: UUID(), username: nil, displayName: "A", directChatID: nil),
            .message(url),
            .currency(url: url, name: "C"),
        ] {
            #expect(!ShareToChatsSheet.isGroupSheet(subject))
            #expect(ShareToChatsSheet.showsRecentChats(for: subject))
        }
    }

    // MARK: - First link and the group-ready card -

    private func privateGroup() -> Conversation {
        Conversation(id: group, members: [], lastMessage: nil, lastActivity: now, type: .group, isPrivate: true)
    }

    @Test("Auto-create fires for a private group only")
    func autoCreateIsPrivateOnly() async {
        let server = Server()
        server.createResults = [.success(.active)]
        let registry = GroupInviteLinksRegistry(service: makeService(server))
        let publicGroup = Conversation(id: group, members: [], lastMessage: nil, lastActivity: now, type: .group, isPrivate: false)

        #expect(registry.autoCreateFirstLink(for: publicGroup) == nil)
        #expect(server.createdSecrets.isEmpty)

        await registry.autoCreateFirstLink(for: privateGroup())?.value
        #expect(server.createdSecrets.count == 1)
    }

    @Test("Auto-create makes one link, with no expiry and no use limit, and only once")
    func autoCreateOnce() async {
        let server = Server()
        server.createResults = [.success(.active), .success(.active)]
        let registry = GroupInviteLinksRegistry(service: makeService(server))

        await registry.autoCreateFirstLink(for: privateGroup())?.value
        #expect(registry.autoCreateFirstLink(for: privateGroup()) == nil)

        #expect(server.createdExpiries == [nil])
        #expect(server.createdMaxUses == [0])
        #expect(registry.links(for: group).current != nil)
    }

    @Test("A failed auto-create is swallowed and the first share makes the link")
    func autoCreateFailureFallsBack() async throws {
        let server = Server()
        server.createResults = [.failure(.denied), .success(.active)]
        let registry = GroupInviteLinksRegistry(service: makeService(server))

        await registry.autoCreateFirstLink(for: privateGroup())?.value
        #expect(registry.links(for: group).current == nil)

        _ = try await registry.links(for: group).currentLink()
        #expect(server.createdSecrets.count == 2)
        #expect(server.createdExpiries.last == .some(nil))
    }

    @Test("The card's tap during the auto-create waits on it instead of making a second link")
    func cardTapJoinsInFlightCreate() async throws {
        let server = Server()
        server.createResults = [.success(.active), .success(.active)]
        server.holdCreate = true
        let registry = GroupInviteLinksRegistry(service: makeService(server))

        let auto = registry.autoCreateFirstLink(for: privateGroup())
        while server.createdSecrets.isEmpty { await Task.yield() }
        let links = registry.links(for: group)
        #expect(links.isCreating)

        let tap = Task { try await links.currentLink() }
        for _ in 0..<20 { await Task.yield() }
        server.holdCreate = false
        let url = try await tap.value
        await auto?.value

        #expect(server.createdSecrets.count == 1)
        #expect(links.current?.url == url)
    }

    @Test("The card's tap with a link present shares it without a create")
    func cardTapWithLink() async throws {
        let server = Server()
        server.invites = [invite(1)]
        let links = makeLinks(server)

        _ = try await links.currentLink()
        #expect(server.createdSecrets.isEmpty)
    }

    @Test("The card's tap with no active link makes one that never expires")
    func cardTapWithoutLink() async throws {
        let server = Server()
        server.invites = [invite(1, status: .revoked)]
        server.createResults = [.success(.active)]
        let links = makeLinks(server)

        _ = try await links.currentLink()

        #expect(server.createdExpiries == [nil])
        #expect(server.createdMaxUses == [0])
    }

    @Test("With Approve New Members on, the card shares the plain link")
    func cardTargetFollowsApprove() {
        #expect(GroupReadyInvite.target(isApproving: true) == .plainLink)
        #expect(GroupReadyInvite.target(isApproving: false) == .currentLink)
    }

    @Test("Invite People closes after a failed link unless the viewer took the plain link or Manage Invites")
    func sheetClosesAfterFailedLink() {
        #expect(GroupReadyInvite.closesSheetAfterFailedLink(sharesPlainLink: false, opensManageInvites: false))
        #expect(!GroupReadyInvite.closesSheetAfterFailedLink(sharesPlainLink: true, opensManageInvites: false))
        #expect(!GroupReadyInvite.closesSheetAfterFailedLink(sharesPlainLink: false, opensManageInvites: true))
    }
}
