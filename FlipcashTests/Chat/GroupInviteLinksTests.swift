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

    private func makeLinks(_ server: Server, unopenable: Set<InviteID> = []) -> GroupInviteLinks {
        let service = GroupInviteLinks.Service(
            selfUserID: me,
            list: { _ in
                if let error = server.listError { throw error }
                return server.invites
            },
            create: { _, secret, maxUses, expiresAt in
                server.createdSecrets.append(secret)
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
        return GroupInviteLinks(conversationID: group, service: service, now: { now })
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

    @Test("With no active link, the first share makes one for 7 days with no use limit")
    func firstShareCreates() async throws {
        let server = Server()
        server.createResults = [.success(.active)]
        let links = makeLinks(server)

        let url = try await links.currentLink()

        #expect(server.createdSecrets.count == 1)
        #expect(server.createdMaxUses == [0])
        #expect(server.createdExpiries == [now.addingTimeInterval(7 * 86_400)])
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
    }

    @Test("An OK that isn't active is not used as a link")
    func inactiveCreateRejected() async {
        let server = Server()
        server.createResults = [.success(.revoked)]
        let links = makeLinks(server)

        await #expect(throws: GroupInviteLinks.CreatedUnusable.self) { try await links.currentLink() }
        #expect(links.current == nil)
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
}
