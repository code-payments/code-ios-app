//
//  Database+Roster.swift
//  FlipcashStore
//

import Foundation
import FlipcashCore
import SQLite

/// Where a group's locally held roster stands against the server's.
public struct RosterSyncState: Sendable, Equatable {
    /// The greatest roster version applied, from a sync or the stream.
    public let version: UInt64
    /// The group's true member count, as the latest roster summary reported it.
    public let memberCount: UInt64
    /// How many current members are held locally.
    public let heldCount: Int
    /// When the last full sync finished, or `nil` if none has.
    public let syncedAt: Date?
    /// Whether the last full sync stopped at the page cap.
    public let isCapped: Bool
    /// The stream version that revealed a skipped version, or `nil` when the stream has been contiguous.
    public let gapVersion: UInt64?

    /// Whether the group's roster should be paged again from the start.
    public var needsFullSync: Bool {
        syncedAt == nil || gapVersion != nil || (!isCapped && UInt64(heldCount) < memberCount)
    }
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
        let feedCount = try reader.pluck(c.table.select(c.rosterMemberCount).filter(c.id == conversationID.data))?[c.rosterMemberCount] ?? 0
        return RosterSyncState(
            version: row[s.version],
            memberCount: max(row[s.memberCount], feedCount),
            heldCount: held,
            syncedAt: row[s.syncedAt].map(Date.init(timeIntervalSinceReferenceDate:)),
            isCapped: row[s.isCapped],
            gapVersion: row[s.gapVersion]
        )
    }

    /// Starts tracking a group's roster so stream updates are written from now on. Seeds the version
    /// and count from the cached chat row; a no-op when the group is already tracked.
    public func beginTrackingRoster(conversationID: ConversationID) throws {
        let s = RosterSyncTable()
        let c = ConversationTable()
        try writer.transaction {
            let chat = try writer.pluck(c.table.select(c.rosterVersion, c.rosterMemberCount).filter(c.id == conversationID.data))
            try writer.run(s.table.insert(
                or: .ignore,
                s.conversationId <- conversationID.data,
                s.version <- chat?[c.rosterVersion] ?? 0,
                s.memberCount <- chat?[c.rosterMemberCount] ?? 0,
                s.syncedAt <- nil,
                s.isCapped <- false,
                s.gapVersion <- nil
            ))
        }
    }

    // MARK: - Writes -

    /// Merges a paged roster read into a tracked group's roster.
    ///
    /// Per member, the greater version wins against what the stream already wrote. When `isComplete`,
    /// a held row the snapshot lacks is dropped unless its version is newer than `summary.version`,
    /// the version the snapshot is at least as fresh as. When the read stopped early, absent rows are
    /// kept, because they may be on the pages not fetched.
    public func mergeRosterSnapshot(
        _ members: [ConversationMember],
        summary: ConversationRosterSummary,
        isComplete: Bool,
        conversationID: ConversationID,
        now: Date = .now
    ) throws {
        let s = RosterSyncTable()
        let r = RosterMemberTable()
        try writer.transaction {
            guard let sync = try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) else { return }
            var held = try heldVersions(conversationID: conversationID)

            for member in members {
                guard let userID = member.userID else { continue }
                if let existing = held[userID], existing > member.version { continue }
                try writeRosterMember(member, userID: userID, version: member.version, conversationID: conversationID)
                held[userID] = member.version
            }

            if isComplete {
                let snapshotIDs = Set(members.compactMap(\.userID))
                for (userID, version) in held where !snapshotIDs.contains(userID) && version <= summary.version {
                    try deleteRosterMember(userID: userID, conversationID: conversationID)
                }
            }

            let version = sync[s.version]
            let gap = sync[s.gapVersion].flatMap { $0 > summary.version + 1 ? $0 : nil }
            try writer.run(s.table.filter(s.conversationId == conversationID.data).update(
                s.version <- max(version, summary.version),
                s.memberCount <- summary.version >= version ? summary.memberCount : sync[s.memberCount],
                s.syncedAt <- now.timeIntervalSinceReferenceDate,
                s.isCapped <- !isComplete,
                s.gapVersion <- gap
            ))
        }
    }

    /// Rewrites the names and pictures of members a fresh roster page carries, for a tracked group.
    /// A row the stream has since moved past is left alone. Nothing is removed.
    public func refreshRosterMembers(_ members: [ConversationMember], conversationID: ConversationID) throws {
        let s = RosterSyncTable()
        try writer.transaction {
            guard try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) != nil else { return }
            let held = try heldVersions(conversationID: conversationID)
            for member in members {
                guard let userID = member.userID else { continue }
                if let existing = held[userID], existing > member.version { continue }
                try writeRosterMember(member, userID: userID, version: member.version, conversationID: conversationID)
            }
        }
    }

    /// Applies live roster updates to a tracked group, returning `false` when the group is not tracked.
    ///
    /// Each update wins against the member's row only with a greater version. An update more than one
    /// past the greatest applied version records a gap, which ``RosterSyncState/needsFullSync`` reports.
    @discardableResult
    public func applyRosterUpdates(_ updates: [DecodedRosterUpdate], conversationID: ConversationID) throws -> Bool {
        let s = RosterSyncTable()
        var isTracked = false
        try writer.transaction {
            guard let sync = try writer.pluck(s.table.filter(s.conversationId == conversationID.data)) else { return }
            isTracked = true
            var version = sync[s.version]
            var memberCount = sync[s.memberCount]
            var gap = sync[s.gapVersion]
            let held = try heldVersions(conversationID: conversationID)

            for update in updates.sorted(by: { $0.rosterSummary.version < $1.rosterSummary.version }) {
                let updateVersion = update.rosterSummary.version
                if updateVersion > version + 1 {
                    gap = max(gap ?? 0, updateVersion)
                }
                if updateVersion > version {
                    version = updateVersion
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
                s.version <- version,
                s.memberCount <- memberCount,
                s.gapVersion <- gap
            ))
        }
        return isTracked
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
