//
//  HostedLobbies.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.hosted-lobbies")

/// The pending join requests on every private group the signed-in user hosts, newest first.
///
/// Read with `GetLobbyMembers` on chat-list load and on a stream reconnect, and kept live with the
/// stream's `LobbyUpdate`s, which the server sends only to a group's creator.
@MainActor
@Observable
final class HostedLobbies {

    typealias GetMembers = @MainActor @Sendable (ConversationID) async throws -> [LobbyMember]
    typealias WrapKey = @MainActor @Sendable (PublicKey, ConversationID) async throws -> ConversationKeyEnvelope
    typealias Admit = @MainActor @Sendable (ConversationID, UserID, ConversationKeyEnvelope) async throws -> Void
    typealias Deny = @MainActor @Sendable (ConversationID, UserID) async throws -> Void

    private var lobbies: [ConversationID: [LobbyMember]] = [:]
    private var approving: Set<UserID> = []

    @ObservationIgnored private let getMembers: GetMembers
    @ObservationIgnored private let wrapKey: WrapKey
    @ObservationIgnored private let admitMember: Admit
    @ObservationIgnored private let denyMember: Deny

    init(getMembers: @escaping GetMembers, wrapKey: @escaping WrapKey, admitMember: @escaping Admit, denyMember: @escaping Deny) {
        self.getMembers = getMembers
        self.wrapKey = wrapKey
        self.admitMember = admitMember
        self.denyMember = denyMember
    }

    /// The people waiting to join `conversationID`, newest first.
    func requests(for conversationID: ConversationID) -> [LobbyMember] {
        lobbies[conversationID] ?? []
    }

    /// The hosted groups with at least one request, the one with the newest request first.
    var groupsWithRequests: [ConversationID] {
        lobbies
            .filter { !$0.value.isEmpty }
            .sorted { ($0.value.first?.enteredAt ?? .distantPast) > ($1.value.first?.enteredAt ?? .distantPast) }
            .map(\.key)
    }

    /// Whether `userID`'s admission is in flight.
    func isApproving(_ userID: UserID) -> Bool {
        approving.contains(userID)
    }

    /// Rereads every lobby in `hosted` and forgets any group not in it. A group whose read fails
    /// keeps what it had.
    func refresh(hosted: [ConversationID]) async {
        let hostedSet = Set(hosted)
        lobbies = lobbies.filter { hostedSet.contains($0.key) }
        for conversationID in hosted {
            await refresh(conversationID)
        }
    }

    /// Rereads `conversationID`'s lobby.
    func refresh(_ conversationID: ConversationID) async {
        do {
            let members = try await getMembers(conversationID)
            lobbies[conversationID] = Self.ordered(members)
        } catch {
            logger.warning("Failed to read a hosted lobby", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
        }
    }

    /// Applies a lobby change from the event stream.
    func apply(_ event: ConversationStreamEvent) {
        guard case .lobbyChanged(let conversationID, let updates) = event else { return }
        var members = lobbies[conversationID] ?? []
        for update in updates {
            switch update {
            case .memberEntered(let member):
                guard let userID = member.userID else { continue }
                members.removeAll { $0.userID == userID }
                members.append(member)
            case .memberLeft(let userID):
                members.removeAll { $0.userID == userID }
            }
        }
        lobbies[conversationID] = Self.ordered(members)
    }

    /// Hands `member` the group key, wrapped to them on this device, and admits them. A member no
    /// longer in the lobby is dropped as if admitted.
    func approve(_ member: LobbyMember, in conversationID: ConversationID) async throws {
        guard let userID = member.userID, !approving.contains(userID) else { return }
        approving.insert(userID)
        defer { approving.remove(userID) }
        do {
            let envelope = try await wrapKey(member.publicKey, conversationID)
            try await admitMember(conversationID, userID, envelope)
        } catch ErrorAdmitLobbyMember.notInLobby {
            // Withdrawn, or settled on another device. Counts as admitted.
        } catch {
            Analytics.groupJoinRequestApproved(error: error)
            throw error
        }
        remove(userID, from: conversationID)
        Analytics.groupJoinRequestApproved(error: nil)
    }

    /// Turns `member` away. The requester isn't told.
    func deny(_ member: LobbyMember, in conversationID: ConversationID) async throws {
        guard let userID = member.userID else { return }
        do {
            try await denyMember(conversationID, userID)
        } catch {
            Analytics.groupJoinRequestDenied(error: error)
            throw error
        }
        remove(userID, from: conversationID)
        Analytics.groupJoinRequestDenied(error: nil)
    }

    private func remove(_ userID: UserID, from conversationID: ConversationID) {
        lobbies[conversationID]?.removeAll { $0.userID == userID }
    }

    /// Newest first, without members that can't be named or acted on.
    private static func ordered(_ members: [LobbyMember]) -> [LobbyMember] {
        members
            .filter { $0.userID != nil }
            .sorted { ($0.enteredAt ?? .distantPast) > ($1.enteredAt ?? .distantPast) }
    }
}

#if DEBUG
extension HostedLobbies {

    /// Held from first use so a reread doesn't move the stand-ins' request times.
    private static let stubEpoch = Date.now

    /// Stand-in requesters for every empty hosted lobby when launched with
    /// `--stub-join-requests=N`, so the Chats row's request states can be seen with one test
    /// account. DEBUG-only; approving one fails, since no real user is behind it.
    static func stubbedMembers() -> [LobbyMember]? {
        let prefix = "--stub-join-requests="
        guard let count = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })
            .flatMap({ Int($0.dropFirst(prefix.count)) }),
              count > 0
        else { return nil }
        let names = ["Jasper", "Ann", "Bo", "Cy", "Dee"]
        return (0..<count).map { index in
            LobbyMember(
                profile: Profile(displayName: names[index % names.count], phone: nil as Phone?, email: nil, userID: UUID()),
                publicKey: KeyPair.generate()!.publicKey,
                enteredAt: stubEpoch.addingTimeInterval(TimeInterval(-60 * (index + 1)))
            )
        }
    }
}
#endif
