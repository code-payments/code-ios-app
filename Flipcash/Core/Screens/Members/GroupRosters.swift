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

    @ObservationIgnored private let getRoster: GetRoster

    init(getRoster: @escaping GetRoster) {
        self.getRoster = getRoster
    }

    /// Whether `conversationID`'s roster has been read at least once.
    func isLoaded(_ conversationID: ConversationID) -> Bool {
        members[conversationID] != nil
    }

    /// `conversationID`'s members, `creator` first, then the most recently joined.
    func members(for conversationID: ConversationID, creator: UserID?) -> [ConversationMember] {
        Self.ordered(Array((members[conversationID] ?? [:]).values), creator: creator)
    }

    /// Reads `conversationID`'s roster and merges it into what the stream has delivered. A failed
    /// read keeps what was held.
    func refresh(_ conversationID: ConversationID) async {
        do {
            let page = try await getRoster(conversationID)
            merge(page, into: conversationID)
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
                insert(member, userID: userID, into: conversationID)
            case .left(let userID):
                members[conversationID]?[userID] = nil
                departures[conversationID, default: [:]][userID] = update.rosterSummary.version
            case .membershipChanged:
                break
            }
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
