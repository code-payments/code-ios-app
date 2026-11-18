//
//  GroupRosters.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore

nonisolated private let logger = Logger(label: "flipcash.group-rosters")

/// Whether a person is on a group's roster, which a private group's host actions wait on.
enum MembershipCheck: Equatable {
    /// On the roster, or in a public group, which has no check.
    case confirmed
    /// A private group's roster hasn't answered yet.
    case pending
    /// The roster was read and the person isn't on it.
    case notMember
    /// The roster couldn't be read.
    case failed
}

/// The members of each private group whose roster has been read this session.
///
/// Read with `GetRoster` when a member opens the group's profile or member list, and kept live with
/// the stream's `RosterUpdate`s. A page can trail the stream, so it never brings back a member the
/// stream already saw leave, and never replaces an entry the stream delivered at a newer version.
@MainActor
@Observable
final class GroupRosters {

    typealias GetRoster = @MainActor @Sendable (ConversationID) async throws -> [ConversationMember]

    private var members: [ConversationID: [UserID: ConversationMember]] = [:]
    /// The roster version at which each departed member left, so a trailing page can't resurrect them.
    private var departures: [ConversationID: [UserID: UInt64]] = [:]

    /// Members the stream delivered while a read of that chat was in flight. The read was pinned
    /// before them, so its page cannot be taken as proof they are gone.
    private var joinedDuringRead: [ConversationID: Set<UserID>] = [:]

    @ObservationIgnored private let getRoster: GetRoster

    init(getRoster: @escaping GetRoster) {
        self.getRoster = getRoster
    }

    /// Whether `conversationID`'s roster has been read at least once.
    func isLoaded(_ conversationID: ConversationID) -> Bool {
        members[conversationID] != nil
    }

    /// What the roster says about `userID` in `conversation`, without reading anything.
    ///
    /// A public group has no check: its roster can be long and paged, so everyone counts as
    /// confirmed there. A private group is pending until its roster has been read.
    func membership(of userID: UserID, in conversation: Conversation?) -> MembershipCheck {
        guard let conversation, conversation.isPrivate else { return .confirmed }
        guard let roster = members[conversation.id] else { return .pending }
        return roster[userID] != nil ? .confirmed : .notMember
    }

    /// Like ``membership(of:in:)``, reading the roster first when a private group's isn't held. A
    /// read that fails answers ``MembershipCheck/failed``. There is no timeout.
    func checkMembership(of userID: UserID, in conversation: Conversation?) async -> MembershipCheck {
        var result = membership(of: userID, in: conversation)
        if result == .pending, let conversation {
            await refresh(conversation.id)
            result = membership(of: userID, in: conversation)
        }
        return result == .pending ? .failed : result
    }

    /// `conversationID`'s members, `creator` first, then the most recently joined.
    func members(for conversationID: ConversationID, creator: UserID?) -> [ConversationMember] {
        Self.ordered(Array((members[conversationID] ?? [:]).values), creator: creator)
    }

    /// Reads `conversationID`'s roster and merges it into what the stream has delivered. A failed
    /// read keeps what was held.
    ///
    /// The read pages to exhaustion, so it is the whole roster: a held member it leaves out was removed
    /// without the stream naming them (a ban reaches the other members as an undisclosed
    /// `membershipChanged`, which moves the count and nothing else), and is dropped here.
    func refresh(_ conversationID: ConversationID) async {
        joinedDuringRead[conversationID] = []
        defer { joinedDuringRead[conversationID] = nil }
        do {
            let page = try await getRoster(conversationID)
            merge(page, into: conversationID)
            dropMembers(missingFrom: page, in: conversationID)
        } catch {
            logger.warning("Failed to read a group roster", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
        }
    }

    /// Applies the stream's roster changes to any roster already read; others are left for their
    /// first read.
    func apply(_ event: ConversationStreamEvent) {
        guard case .rosterChanged(let conversationID, let updates) = event,
              members[conversationID] != nil else { return }
        for update in updates {
            switch update.change {
            case .joined(let member, _):
                guard let userID = member.userID else { continue }
                departures[conversationID]?[userID] = nil
                joinedDuringRead[conversationID]?.insert(userID)
                insert(member, userID: userID, into: conversationID)
            case .left(let userID):
                members[conversationID]?[userID] = nil
                departures[conversationID, default: [:]][userID] = update.rosterSummary.version
            case .membershipChanged:
                // The update names no one, so the list can't be patched. The count has moved, and a
                // list left as it was would still show whoever was removed: read it again.
                Task { await refresh(conversationID) }
            }
        }
    }

    /// Drops `userID` at once, for a removal this device just made. The server sends the host no
    /// departure for it, and the list should change in the same beat as the count.
    func remove(_ userID: UserID, from conversationID: ConversationID) {
        guard let held = members[conversationID]?[userID] else { return }
        members[conversationID]?[userID] = nil
        departures[conversationID, default: [:]][userID] = held.version
    }

    private func dropMembers(missingFrom page: [ConversationMember], in conversationID: ConversationID) {
        let pageIDs = Set(page.compactMap(\.userID))
        let kept = joinedDuringRead[conversationID] ?? []
        for userID in Array((members[conversationID] ?? [:]).keys) where !pageIDs.contains(userID) && !kept.contains(userID) {
            members[conversationID]?[userID] = nil
        }
    }

    private func merge(_ page: [ConversationMember], into conversationID: ConversationID) {
        if members[conversationID] == nil {
            members[conversationID] = [:]
        }
        let departed = departures[conversationID] ?? [:]
        for member in page {
            guard let userID = member.userID else { continue }
            if let leftAt = departed[userID], leftAt >= member.version { continue }
            insert(member, userID: userID, into: conversationID)
        }
    }

    private func insert(_ member: ConversationMember, userID: UserID, into conversationID: ConversationID) {
        if let held = members[conversationID]?[userID], held.version > member.version { return }
        members[conversationID, default: [:]][userID] = member
    }

    nonisolated static func ordered(_ members: [ConversationMember], creator: UserID?) -> [ConversationMember] {
        members.sorted { lhs, rhs in
            let lhsIsCreator = creator != nil && lhs.userID == creator
            let rhsIsCreator = creator != nil && rhs.userID == creator
            if lhsIsCreator != rhsIsCreator { return lhsIsCreator }
            return (lhs.joinedAt ?? .distantPast) > (rhs.joinedAt ?? .distantPast)
        }
    }
}
