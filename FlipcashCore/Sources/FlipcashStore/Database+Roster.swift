//
//  Database+Roster.swift
//  FlipcashStore
//

import Foundation
import FlipcashCore
import SQLite

/// Where a group's locally held roster stands against the server's.
public struct RosterSyncState: Sendable, Equatable {
    /// The last roster version a `Chat.GetRoster` read fully applied.
    public let watermark: UInt64
    /// The greatest roster version seen from the stream, the chat feed, or a read.
    public let observedVersion: UInt64
    /// The group's member count, as the latest roster summary reported it.
    public let memberCount: UInt64
    /// How many current members are held locally.
    public let heldCount: Int
    /// Whether a full read has ever finished.
    public let fullySynced: Bool
    /// Whether the last full read stopped at the page cap.
    public let truncated: Bool
    /// Whether a full read is owed, from an unseen leave or a read that couldn't drop members.
    public let reconcilePending: Bool

    /// Whether the roster should be read from the first page to the end.
    public var needsFullRead: Bool { !fullySynced || reconcilePending }

    /// Whether the roster moved past what a read has applied, so the newest pages should be re-read.
    public var needsCatchUp: Bool { observedVersion > watermark }
}

/// What a catch-up read found once merged.
public enum RosterCatchUpOutcome: Sendable, Equatable {
    /// The held roster agrees with the page's count; the watermark moved to the page's version.
    case caughtUp
    /// More members are held than the page counts, so someone left unseen; a full read is owed.
    case reconcileNeeded
}

/// A current roster member as stored, with the key roster search sorts it by.
public struct RosterEntry: Sendable, Equatable {
    public let member: ConversationMember
    /// ``RosterSearchText/normalize(_:)`` of the display name.
    public let sortKey: String
}

nonisolated extension Database {

    // MARK: - Sync state -

    /// Returns the roster sync state for a group, or `nil` when its roster is not tracked yet.
    public func rosterSyncState(conversationID: ConversationID) throws -> RosterSyncState? {
        let s = RosterSyncTable()
        let r = RosterMemberTable()
        let c = ConversationTable()
        guard let row = try reader.pluck(s.table.filter(s.conversationId == conversationID.data)) else {
            return nil
        }
        let held = try reader.scalar(r.table.filter(r.conversationId == conversationID.data && r.isMember == true).count)
        let feedVersion = try reader.pluck(c.table.select(c.rosterVersion).filter(c.id == conversationID.data))?[c.rosterVersion] ?? 0
        return RosterSyncState(
            watermark: row[s.watermark],
            observedVersion: max(row[s.observedVersion], feedVersion),
            memberCount: row[s.memberCount],
            heldCount: held,
            fullySynced: row[s.fullySynced],
            truncated: row[s.truncated],
            reconcilePending: row[s.reconcilePending]
        )
    }

    /// Starts tracking a group's roster so stream updates are written from now on. A no-op when the
    /// group is already tracked.
    public func beginTrackingRoster(conversationID: ConversationID) throws {
        let s = RosterSyncTable()
        let c = ConversationTable()
        try writer.transaction {
            let chat = try writer.pluck(c.table.select(c.rosterVersion, c.rosterMemberCount).filter(c.id == conversationID.data))
            try writer.run(s.table.insert(
                or: .ignore,
                s.conversationId <- conversationID.data,
                s.watermark <- 0,
                s.observedVersion <- chat?[c.rosterVersion] ?? 0,
                s.memberCount <- chat?[c.rosterMemberCount] ?? 0,
                s.fullySynced <- false,
                s.truncated <- false,
                s.reconcilePending <- false
            ))
        }
    }

    // MARK: - Writes -

    /// Merges a read from the first page to the end, or to the page cap, into a tracked group.
    ///
    /// Per member, the greater version wins against what the stream already wrote. A held member the
    /// read lacks is dropped only when the read reached the end, every page reported the same roster
    /// version, and the held row's version is not above it. When the pages disagree, nothing is
    /// dropped and a reconcile stays pending. A truncated read drops nothing and owes nothing: the
    /// members past the cap were never held.
    public func applyFullRosterRead(
        _ members: [ConversationMember],
        summaries: [ConversationRosterSummary],
        isComplete: Bool,
        conversationID: ConversationID
    ) throws {
        guard let oldest = summaries.min(by: { $0.version < $1.version }),
              let newest = summaries.max(by: { $0.version < $1.version }) else { return }
        let isConsistent = oldest.version == newest.version
        let s = RosterSyncTable()
        try writer.transaction {
            guard let sync = try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) else { return }
            var held = try mergeRosterMembers(members, conversationID: conversationID)

            if isComplete && isConsistent {
                let readIDs = Set(members.compactMap(\.userID))
                for (userID, version) in held where !readIDs.contains(userID) && version <= oldest.version {
                    try deleteRosterMember(userID: userID, conversationID: conversationID)
                    held[userID] = nil
                }
            }

            try writer.run(s.table.filter(s.conversationId == conversationID.data).update(
                s.watermark <- max(sync[s.watermark], oldest.version),
                s.observedVersion <- max(sync[s.observedVersion], newest.version),
                s.memberCount <- oldest.memberCount,
                s.fullySynced <- true,
                s.truncated <- !isComplete,
                s.reconcilePending <- !isConsistent
            ))
        }
    }

    /// Merges a read of the newest pages into a tracked group and checks the page's count for leaves
    /// the read can't show.
    ///
    /// `summary` is the page's roster summary; with several pages, the one with the lowest version.
    /// When no more members are held than it counts, the watermark moves to its version: a join the
    /// read missed is newer than the page and arrives on the stream. When more are held, someone left
    /// unseen, so a reconcile is recorded and the watermark stays put.
    public func applyRosterCatchUp(
        _ members: [ConversationMember],
        summary: ConversationRosterSummary,
        conversationID: ConversationID
    ) throws -> RosterCatchUpOutcome {
        let s = RosterSyncTable()
        let r = RosterMemberTable()
        var outcome = RosterCatchUpOutcome.caughtUp
        try writer.transaction {
            guard let sync = try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) else { return }
            try mergeRosterMembers(members, conversationID: conversationID)
            let held = try writer.scalar(r.table.filter(r.conversationId == conversationID.data && r.isMember == true).count)
            let observed = max(sync[s.observedVersion], summary.version)

            if UInt64(held) > summary.memberCount {
                outcome = .reconcileNeeded
                try writer.run(s.table.filter(s.conversationId == conversationID.data).update(
                    s.observedVersion <- observed,
                    s.reconcilePending <- true
                ))
            } else {
                try writer.run(s.table.filter(s.conversationId == conversationID.data).update(
                    s.watermark <- max(sync[s.watermark], summary.version),
                    s.observedVersion <- observed,
                    s.memberCount <- summary.memberCount
                ))
            }
        }
        return outcome
    }

    /// Applies live roster updates to a tracked group, returning `false` when the group is not tracked.
    ///
    /// Each update wins against the member's row only with a greater version. The watermark does not
    /// move: the stream can't show whether an update was skipped, so the next open catches up from
    /// the roster's first page instead.
    @discardableResult
    public func applyRosterUpdates(_ updates: [DecodedRosterUpdate], conversationID: ConversationID) throws -> Bool {
        let s = RosterSyncTable()
        var isTracked = false
        try writer.transaction {
            guard let sync = try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) else { return }
            isTracked = true
            var observed = sync[s.observedVersion]
            var memberCount = sync[s.memberCount]
            let held = try heldVersions(conversationID: conversationID)

            for update in updates.sorted(by: { $0.rosterSummary.version < $1.rosterSummary.version }) {
                let updateVersion = update.rosterSummary.version
                if updateVersion > observed {
                    observed = updateVersion
                    memberCount = update.rosterSummary.memberCount
                }

                switch update.change {
                case .joined(let member, _):
                    guard let userID = member.userID else { continue }
                    if let existing = held[userID], existing >= updateVersion { continue }
                    try writeRosterMember(member, userID: userID, version: updateVersion, conversationID: conversationID)
                case .left(let userID):
                    if let existing = held[userID], existing >= updateVersion { continue }
                    try writeRosterDeparture(userID: userID, version: updateVersion, conversationID: conversationID)
                }
            }

            try writer.run(s.table.filter(s.conversationId == conversationID.data).update(
                s.observedVersion <- observed,
                s.memberCount <- memberCount
            ))
        }
        return isTracked
    }

    /// Must be called inside a `writer.transaction`. Rewrites a user's name, username, picture, and
    /// search tokens in every group that holds them as a current member, keeping each row's version,
    /// since a profile change doesn't move the roster version.
    func refreshRosterProfile(_ profile: Profile, userID: UserID) throws {
        let r = RosterMemberTable()
        let t = RosterTokenTable()
        let rows = try Array(writer.prepareRowIterator(
            r.table.filter(r.userId == userID && r.isMember == true)
        ))
        for row in rows {
            let conversationData = row[r.conversationId]
            let displayName = profile.displayName ?? row[r.displayName]
            try writer.run(r.table.filter(r.conversationId == conversationData && r.userId == userID).update(
                r.displayName <- displayName,
                r.username <- profile.username?.value,
                r.profilePictureBlobID <- profile.profilePicture?.blobID.data,
                r.profilePictureThumbnailBlobID <- profile.profilePicture?.thumbnailBlobID.data,
                r.profilePictureThumbnailBlurhash <- profile.profilePicture?.thumbnailBlurhash,
                r.sortKey <- RosterSearchText.normalize(displayName)
            ))
            try writer.run(t.table.filter(t.conversationId == conversationData && t.userId == userID).delete())
            for token in RosterSearchText.tokens(displayName: displayName, username: profile.username?.value) {
                try writer.run(t.table.insert(or: .ignore, t.conversationId <- conversationData, t.token <- token, t.userId <- userID))
            }
        }
    }

    /// Removes everything held for a group's roster, tracking included.
    public func deleteRoster(conversationID: ConversationID) throws {
        try writer.transaction {
            try deleteRosterRows(conversationIDs: [conversationID.data])
        }
    }

    // MARK: - Reads -

    /// Returns the ids of current members with, for every word in `prefixes`, a token starting with it.
    /// Each word is one index range scan over `(conversationId, token)`.
    public func rosterMemberIDs(matchingPrefixes prefixes: [String], conversationID: ConversationID) throws -> Set<UserID> {
        let t = RosterTokenTable()
        var matched: Set<UserID>?
        for prefix in prefixes {
            let query = t.table
                .select(distinct: t.userId)
                .filter(t.conversationId == conversationID.data
                    && t.token >= prefix
                    && t.token < RosterSearchText.prefixUpperBound(prefix))
            let ids = Set(try reader.prepareRowIterator(query).map { $0[t.userId] })
            matched = matched.map { $0.intersection(ids) } ?? ids
            if matched?.isEmpty == true { break }
        }
        return matched ?? []
    }

    /// Returns the current members of a group, limited to `userIDs` when given.
    public func rosterEntries(conversationID: ConversationID, userIDs: Set<UserID>? = nil) throws -> [RosterEntry] {
        let r = RosterMemberTable()
        var query = r.table.filter(r.conversationId == conversationID.data && r.isMember == true)
        if let userIDs {
            query = query.filter(userIDs.contains(r.userId))
        }
        return try reader.prepareRowIterator(query).map { row in
            RosterEntry(
                member: ConversationMember(
                    userID: row[r.userId],
                    displayName: row[r.displayName],
                    profilePicture: rosterProfilePicture(from: row),
                    username: row[r.username].flatMap(Username.init),
                    joinedAt: row[r.joinedAt].map(Date.init(timeIntervalSinceReferenceDate:)),
                    version: row[r.version]
                ),
                sortKey: row[r.sortKey]
            )
        }
    }

    /// Returns who sent the newest `window` held messages of a conversation, most recent sender first,
    /// each once.
    public func recentSenders(conversationID: ConversationID, window: Int) throws -> [UserID] {
        let m = ConversationMessageTable()
        let query = m.table
            .select(m.senderId)
            .filter(m.conversationId == conversationID.data)
            .order(m.id.desc)
            .limit(window)
        var seen: Set<UserID> = []
        var senders: [UserID] = []
        for row in try Array(reader.prepareRowIterator(query)) {
            guard let sender = row[m.senderId], seen.insert(sender).inserted else { continue }
            senders.append(sender)
        }
        return senders
    }

    // MARK: - Private -

    /// Must be called inside a `writer.transaction`. Deletes every roster row for the given chats.
    func deleteRosterRows(conversationIDs: [Data]) throws {
        guard !conversationIDs.isEmpty else { return }
        let r = RosterMemberTable()
        let t = RosterTokenTable()
        let s = RosterSyncTable()
        try writer.run(r.table.filter(conversationIDs.contains(r.conversationId)).delete())
        try writer.run(t.table.filter(conversationIDs.contains(t.conversationId)).delete())
        try writer.run(s.table.filter(conversationIDs.contains(s.conversationId)).delete())
    }

    /// Must be called inside a `writer.transaction`. Every held row's version, departures included.
    private func heldVersions(conversationID: ConversationID) throws -> [UserID: UInt64] {
        let r = RosterMemberTable()
        let query = r.table.select(r.userId, r.version).filter(r.conversationId == conversationID.data)
        var versions: [UserID: UInt64] = [:]
        for row in try Array(writer.prepareRowIterator(query)) {
            versions[row[r.userId]] = row[r.version]
        }
        return versions
    }

    /// Must be called inside a `writer.transaction`. Writes each member whose version is not below the
    /// held row's, so an equal version refreshes a name or picture. Returns every held row's version.
    @discardableResult
    private func mergeRosterMembers(_ members: [ConversationMember], conversationID: ConversationID) throws -> [UserID: UInt64] {
        var held = try heldVersions(conversationID: conversationID)
        for member in members {
            guard let userID = member.userID else { continue }
            if let existing = held[userID], existing > member.version { continue }
            try writeRosterMember(member, userID: userID, version: member.version, conversationID: conversationID)
            held[userID] = member.version
        }
        return held
    }

    /// Must be called inside a `writer.transaction`.
    private func writeRosterMember(_ member: ConversationMember, userID: UserID, version: UInt64, conversationID: ConversationID) throws {
        let r = RosterMemberTable()
        let t = RosterTokenTable()
        try writer.run(r.table.insert(
            or: .replace,
            r.conversationId <- conversationID.data,
            r.userId <- userID,
            r.displayName <- member.displayName,
            r.username <- member.username?.value,
            r.profilePictureBlobID <- member.profilePicture?.blobID.data,
            r.profilePictureThumbnailBlobID <- member.profilePicture?.thumbnailBlobID.data,
            r.profilePictureThumbnailBlurhash <- member.profilePicture?.thumbnailBlurhash,
            r.joinedAt <- member.joinedAt?.timeIntervalSinceReferenceDate,
            r.version <- version,
            r.isMember <- true,
            r.sortKey <- RosterSearchText.normalize(member.displayName)
        ))
        try deleteRosterTokens(userID: userID, conversationID: conversationID)
        for token in RosterSearchText.tokens(displayName: member.displayName, username: member.username?.value) {
            try writer.run(t.table.insert(
                or: .ignore,
                t.conversationId <- conversationID.data,
                t.token <- token,
                t.userId <- userID
            ))
        }
    }

    /// Must be called inside a `writer.transaction`. Keeps a departed member's row, so a trailing
    /// roster page can't bring them back, and drops them from the index.
    private func writeRosterDeparture(userID: UserID, version: UInt64, conversationID: ConversationID) throws {
        let r = RosterMemberTable()
        try writer.run(r.table.insert(
            or: .replace,
            r.conversationId <- conversationID.data,
            r.userId <- userID,
            r.displayName <- "",
            r.username <- nil,
            r.profilePictureBlobID <- nil,
            r.profilePictureThumbnailBlobID <- nil,
            r.profilePictureThumbnailBlurhash <- nil,
            r.joinedAt <- nil,
            r.version <- version,
            r.isMember <- false,
            r.sortKey <- ""
        ))
        try deleteRosterTokens(userID: userID, conversationID: conversationID)
    }

    /// Must be called inside a `writer.transaction`.
    private func deleteRosterMember(userID: UserID, conversationID: ConversationID) throws {
        let r = RosterMemberTable()
        try writer.run(r.table.filter(r.conversationId == conversationID.data && r.userId == userID).delete())
        try deleteRosterTokens(userID: userID, conversationID: conversationID)
    }

    /// Must be called inside a `writer.transaction`.
    private func deleteRosterTokens(userID: UserID, conversationID: ConversationID) throws {
        let t = RosterTokenTable()
        try writer.run(t.table.filter(t.conversationId == conversationID.data && t.userId == userID).delete())
    }

    private func rosterProfilePicture(from row: RowIterator.Element) -> ProfilePicture? {
        let r = RosterMemberTable()
        guard let blobID = row[r.profilePictureBlobID],
              let thumbnailBlobID = row[r.profilePictureThumbnailBlobID] else {
            return nil
        }
        return ProfilePicture(
            blobID: BlobID(data: blobID),
            thumbnailBlobID: BlobID(data: thumbnailBlobID),
            thumbnailBlurhash: row[r.profilePictureThumbnailBlurhash]
        )
    }
}
