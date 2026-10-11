//
//  LobbyRequestsTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Private group join requests")
struct LobbyRequestsTests {

    private let owner = KeyPair.generate()!.publicKey

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "lobby-requests-\(UUID())")!
    }

    private func group(_ id: ConversationID, inLobby: Bool) -> Conversation {
        Conversation(id: id, members: [], lastMessage: nil, lastActivity: .distantPast, type: .group, isPrivate: true, inLobby: inLobby)
    }

    private func makeRequests(
        defaults: UserDefaults,
        enter: @escaping LobbyRequests.EnterLobby = { _ in throw ErrorEnterLobby.denied },
        leave: @escaping LobbyRequests.LeaveLobby = { _ in }
    ) -> LobbyRequests {
        LobbyRequests(defaults: defaults, owner: owner, enterLobby: enter, leaveLobby: leave)
    }

    @Test("A request records when the lobby says it was entered")
    func requestRecordsEnteredAt() async throws {
        let id = ConversationID.test(1)
        let entered = Date(timeIntervalSince1970: 1_000)
        let requests = makeRequests(defaults: makeDefaults(), enter: { [self] id in
            Lobby(conversation: group(id, inLobby: true), enteredAt: entered)
        })

        let outcome = try await requests.request(id)

        #expect(outcome == .requested)
        #expect(requests.requestedAt(id) == entered)
    }

    @Test("Requests survive a relaunch for the same owner")
    func persistsAcrossInstances() async throws {
        let id = ConversationID.test(2)
        let defaults = makeDefaults()
        let entered = Date(timeIntervalSince1970: 2_000)
        let first = makeRequests(defaults: defaults, enter: { [self] id in
            Lobby(conversation: group(id, inLobby: true), enteredAt: entered)
        })
        _ = try await first.request(id)

        let second = makeRequests(defaults: defaults)

        #expect(second.requestedAt(id) == entered)
    }

    @Test("A full lobby throws the sheet's error and records nothing", arguments: [
        (ErrorEnterLobby.lobbyFull, LobbyRequests.RequestError.lobbyFull),
        (ErrorEnterLobby.tooManyLobbies, LobbyRequests.RequestError.tooManyLobbies),
    ])
    func fullLobbyThrows(server: ErrorEnterLobby, expected: LobbyRequests.RequestError) async {
        let id = ConversationID.test(3)
        let requests = makeRequests(defaults: makeDefaults(), enter: { _ in throw server })

        await #expect(throws: expected) { try await requests.request(id) }
        #expect(requests.requestedAt(id) == nil)
    }

    @Test("Already a member is not a pending request")
    func alreadyMember() async throws {
        let id = ConversationID.test(4)
        let requests = makeRequests(defaults: makeDefaults(), enter: { _ in throw ErrorEnterLobby.alreadyMember })

        let outcome = try await requests.request(id)

        #expect(outcome == .alreadyMember)
        #expect(requests.requestedAt(id) == nil)
    }

    @Test("Cancel leaves the lobby and forgets the request")
    func cancelForgets() async throws {
        let id = ConversationID.test(5)
        var left: [ConversationID] = []
        let requests = makeRequests(
            defaults: makeDefaults(),
            enter: { [self] id in Lobby(conversation: group(id, inLobby: true), enteredAt: .now) },
            leave: { left.append($0) }
        )
        _ = try await requests.request(id)

        try await requests.cancel(id)

        #expect(left == [id])
        #expect(requests.requestedAt(id) == nil)
    }

    @Test("A failed cancel keeps the request")
    func failedCancelKeeps() async throws {
        let id = ConversationID.test(6)
        let requests = makeRequests(
            defaults: makeDefaults(),
            enter: { [self] id in Lobby(conversation: group(id, inLobby: true), enteredAt: .now) },
            leave: { _ in throw ErrorLeaveLobby.denied }
        )
        _ = try await requests.request(id)

        await #expect(throws: (any Error).self) { try await requests.cancel(id) }
        #expect(requests.requestedAt(id) != nil)
    }

    @Test("GetChat out of the lobby settles a pending request")
    func reconcileClears() async throws {
        let id = ConversationID.test(7)
        let requests = makeRequests(defaults: makeDefaults(), enter: { [self] id in
            Lobby(conversation: group(id, inLobby: true), enteredAt: .now)
        })
        _ = try await requests.request(id)

        requests.reconcile(with: group(id, inLobby: false))

        #expect(requests.requestedAt(id) == nil)
    }

    @Test("GetChat in the lobby adopts a request made on another device")
    func reconcileAdopts() {
        let id = ConversationID.test(8)
        let now = Date(timeIntervalSince1970: 3_000)
        let requests = makeRequests(defaults: makeDefaults())

        requests.reconcile(with: group(id, inLobby: true), now: now)

        #expect(requests.requestedAt(id) == now)
    }
}

@MainActor
@Suite("Private group copy")
struct PrivateGroupCopyTests {

    private let requested = Date(timeIntervalSince1970: 100_000)

    @Test("Pending title ages from Request Sent", arguments: [
        (0, "Request Sent"),
        (59, "Request Sent"),
        (60, "Requested 1m ago"),
        (10 * 60, "Requested 10m ago"),
        (2 * 3600, "Requested 2h ago"),
        (3 * 86400, "Requested 3d ago"),
    ])
    func pendingTitle(seconds: Int, expected: String) {
        let now = requested.addingTimeInterval(TimeInterval(seconds))
        #expect(PrivateGroupCopy.pendingTitle(requestedAt: requested, now: now) == expected)
    }

    @Test("Awaiting approval names the host, without a trailing period")
    func awaitingApproval() {
        #expect(PrivateGroupCopy.awaitingApproval(hostName: "Ana") == "You'll be able to open the chat once Ana approves")
        #expect(PrivateGroupCopy.awaitingApproval(hostName: nil) == "You'll be able to open the chat once the host approves")
        #expect(PrivateGroupCopy.awaitingApproval(hostName: "") == "You'll be able to open the chat once the host approves")
    }

    @Test("Summary counts members")
    func summary() {
        #expect(PrivateGroupCopy.summary(memberCount: 0) == "Private group")
        #expect(PrivateGroupCopy.summary(memberCount: 1) == "Private group · 1 member")
        #expect(PrivateGroupCopy.summary(memberCount: 48) == "Private group · 48 members")
    }
}
