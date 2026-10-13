//
//  HostedLobbiesTests.swift
//  FlipcashTests
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Testing
import FlipcashCore
@testable import Flipcash

@MainActor
@Suite("Hosted private group join requests")
struct HostedLobbiesTests {

    private let group = ConversationID.test(1)
    private let envelope = ConversationKeyEnvelope(scheme: 1, nonce: Data(repeating: 1, count: 24), ciphertext: Data(repeating: 2, count: 48))

    private func member(_ name: String, enteredAt seconds: TimeInterval, userID: UserID? = UUID()) -> LobbyMember {
        LobbyMember(
            profile: Profile(displayName: name, phone: nil as Phone?, email: nil, userID: userID),
            publicKey: KeyPair.generate()!.publicKey,
            enteredAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private func makeLobbies(
        members: [ConversationID: [LobbyMember]] = [:],
        wrapKey: @escaping HostedLobbies.WrapKey = { _, _ in throw ErrorAdmitLobbyMember.denied },
        admit: @escaping HostedLobbies.Admit = { _, _, _ in },
        deny: @escaping HostedLobbies.Deny = { _, _ in }
    ) -> HostedLobbies {
        HostedLobbies(
            getMembers: { members[$0] ?? [] },
            wrapKey: wrapKey,
            admitMember: admit,
            denyMember: deny
        )
    }

    @Test("A refresh lists requests newest first and drops ones without a user id")
    func refreshOrdersNewestFirst() async {
        let older = member("Ann", enteredAt: 100)
        let newer = member("Bo", enteredAt: 200)
        let unnamed = member("?", enteredAt: 300, userID: nil)
        let lobbies = makeLobbies(members: [group: [older, unnamed, newer]])

        await lobbies.refresh(hosted: [group])

        #expect(lobbies.requests(for: group).map(\.userID) == [newer.userID, older.userID])
        #expect(lobbies.groupsWithRequests == [group])
    }

    @Test("A refresh forgets groups the user no longer hosts")
    func refreshForgetsUnhosted() async {
        let other = ConversationID.test(2)
        let lobbies = makeLobbies(members: [group: [member("Ann", enteredAt: 1)], other: [member("Bo", enteredAt: 2)]])
        await lobbies.refresh(hosted: [group, other])

        await lobbies.refresh(hosted: [group])

        #expect(lobbies.requests(for: other).isEmpty)
        #expect(lobbies.groupsWithRequests == [group])
    }

    @Test("Groups are ordered by their newest request")
    func groupsOrderedByNewestRequest() async {
        let other = ConversationID.test(2)
        let lobbies = makeLobbies(members: [group: [member("Ann", enteredAt: 100)], other: [member("Bo", enteredAt: 500)]])

        await lobbies.refresh(hosted: [group, other])

        #expect(lobbies.groupsWithRequests == [other, group])
    }

    @Test("Stream updates insert at the front, replace repeats and remove leavers")
    func streamUpdates() async {
        let ann = member("Ann", enteredAt: 100)
        let bo = member("Bo", enteredAt: 200)
        let lobbies = makeLobbies()

        lobbies.apply(.lobbyChanged(conversationID: group, updates: [.memberEntered(ann), .memberEntered(bo), .memberEntered(ann)]))
        #expect(lobbies.requests(for: group).map(\.userID) == [bo.userID, ann.userID])

        lobbies.apply(.lobbyChanged(conversationID: group, updates: [.memberLeft(userID: bo.userID!)]))
        #expect(lobbies.requests(for: group).map(\.userID) == [ann.userID])
    }

    @Test("Approve wraps the key to the requester's public key, admits them and removes the row")
    func approveWrapsAndAdmits() async throws {
        let ann = member("Ann", enteredAt: 100)
        var wrappedFor: PublicKey?
        var admitted: (ConversationID, UserID, ConversationKeyEnvelope)?
        let lobbies = makeLobbies(
            members: [group: [ann]],
            wrapKey: { [envelope] key, _ in wrappedFor = key; return envelope },
            admit: { admitted = ($0, $1, $2) }
        )
        await lobbies.refresh(hosted: [group])

        try await lobbies.approve(ann, in: group)

        #expect(wrappedFor == ann.publicKey)
        #expect(admitted?.0 == group)
        #expect(admitted?.1 == ann.userID)
        #expect(admitted?.2 == envelope)
        #expect(lobbies.requests(for: group).isEmpty)
        #expect(!lobbies.isApproving(ann.userID!))
    }

    @Test("Approving someone who already left the lobby removes their row without an error")
    func approveNotInLobbyRemovesRow() async throws {
        let ann = member("Ann", enteredAt: 100)
        let lobbies = makeLobbies(
            members: [group: [ann]],
            wrapKey: { [envelope] _, _ in envelope },
            admit: { _, _, _ in throw ErrorAdmitLobbyMember.notInLobby }
        )
        await lobbies.refresh(hosted: [group])

        try await lobbies.approve(ann, in: group)

        #expect(lobbies.requests(for: group).isEmpty)
    }

    @Test("A failed approval keeps the row and rethrows")
    func approveFailureKeepsRow() async {
        let ann = member("Ann", enteredAt: 100)
        let lobbies = makeLobbies(
            members: [group: [ann]],
            wrapKey: { [envelope] _, _ in envelope },
            admit: { _, _, _ in throw ErrorAdmitLobbyMember.denied }
        )
        await lobbies.refresh(hosted: [group])

        await #expect(throws: ErrorAdmitLobbyMember.denied) {
            try await lobbies.approve(ann, in: group)
        }
        #expect(lobbies.requests(for: group).map(\.userID) == [ann.userID])
        #expect(!lobbies.isApproving(ann.userID!))
    }

    @Test("The stream's leave after an approval is a no-op")
    func streamLeaveAfterApproveIsNoOp() async throws {
        let ann = member("Ann", enteredAt: 100)
        let bo = member("Bo", enteredAt: 200)
        let lobbies = makeLobbies(members: [group: [ann, bo]], wrapKey: { [envelope] _, _ in envelope })
        await lobbies.refresh(hosted: [group])

        try await lobbies.approve(ann, in: group)
        lobbies.apply(.lobbyChanged(conversationID: group, updates: [.memberLeft(userID: ann.userID!)]))

        #expect(lobbies.requests(for: group).map(\.userID) == [bo.userID])
    }

    @Test("Deny calls DenyLobbyMember and removes the row")
    func denyRemovesRow() async throws {
        let ann = member("Ann", enteredAt: 100)
        var denied: UserID?
        let lobbies = makeLobbies(members: [group: [ann]], deny: { _, userID in denied = userID })
        await lobbies.refresh(hosted: [group])

        try await lobbies.deny(ann, in: group)

        #expect(denied == ann.userID)
        #expect(lobbies.requests(for: group).isEmpty)
    }

    @Test("A failed deny keeps the row")
    func denyFailureKeepsRow() async {
        let ann = member("Ann", enteredAt: 100)
        let lobbies = makeLobbies(members: [group: [ann]], deny: { _, _ in throw ErrorDenyLobbyMember.denied })
        await lobbies.refresh(hosted: [group])

        await #expect(throws: ErrorDenyLobbyMember.denied) {
            try await lobbies.deny(ann, in: group)
        }
        #expect(lobbies.requests(for: group).count == 1)
    }
}
