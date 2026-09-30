//
//  RosterSync.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import FlipcashStore

nonisolated private let logger = Logger(label: "flipcash.roster-sync")

/// Keeps the full roster of each group the user opens on device, for member search.
///
/// A group is tracked from its first open: ``syncIfNeeded(_:)`` pages `Chat.GetRoster` into the
/// store, and ``apply(_:)`` keeps it current from the event stream's roster updates. Groups never
/// opened are not fetched. Both paths merge per member by roster version, greater winning, so a page
/// that trails the stream and a stream update that races a sync converge on the same roster.
actor RosterSync {

    /// Pages fetched before a sync stops, `has_more` or not; at 100 per page, 2,000 members.
    static let defaultPageCap = 20

    private let fetching: any RosterFetching
    private let database: Database
    private let owner: KeyPair
    private let pageCap: Int

    /// Full syncs in flight, so a second open of the same group joins the first rather than paging twice.
    private var inFlight: [ConversationID: Task<Void, Never>] = [:]

    init(fetching: any RosterFetching, database: Database, owner: KeyPair, pageCap: Int = RosterSync.defaultPageCap) {
        self.fetching = fetching
        self.database = database
        self.owner = owner
        self.pageCap = pageCap
    }

    /// Starts tracking a group and pages its full roster when it has never been fully synced, holds
    /// fewer members than it has, or the stream skipped a version. Returns once any sync is done.
    func syncIfNeeded(_ conversationID: ConversationID) async {
        if let running = inFlight[conversationID] {
            await running.value
            return
        }
        do {
            try database.beginTrackingRoster(conversationID: conversationID)
            guard try database.rosterSyncState(conversationID: conversationID)?.needsFullSync ?? true else { return }
        } catch {
            await report(error, reason: "Failed to read roster sync state", conversationID: conversationID)
            return
        }
        let task = Task { await self.pageFullRoster(conversationID) }
        inFlight[conversationID] = task
        await task.value
        inFlight[conversationID] = nil
    }

    /// Rewrites the held names and pictures of a group's most recently joined members from a fresh
    /// first page, since profile changes don't bump the roster version. Runs a full sync instead when
    /// one is due.
    func refreshFirstPage(_ conversationID: ConversationID) async {
        do {
            try database.beginTrackingRoster(conversationID: conversationID)
            let needsFullSync = try database.rosterSyncState(conversationID: conversationID)?.needsFullSync ?? true
            if needsFullSync || inFlight[conversationID] != nil {
                await syncIfNeeded(conversationID)
                return
            }
            let page = try await fetching.getRosterPage(owner: owner, conversationID: conversationID, pagingToken: nil)
            try database.refreshRosterMembers(page.members, conversationID: conversationID)
        } catch {
            await report(error, reason: "Failed to refresh roster first page", conversationID: conversationID)
        }
    }

    /// Writes a stream roster update into the held roster of a tracked group; other events are ignored.
    @MainActor
    func apply(_ event: ConversationStreamEvent) {
        guard case .rosterChanged(let conversationID, let updates) = event else { return }
        do {
            try database.applyRosterUpdates(updates, conversationID: conversationID)
        } catch {
            logger.error("Failed to apply roster updates", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            ErrorReporting.captureError(error, reason: "Failed to apply roster updates")
        }
    }

    private func pageFullRoster(_ conversationID: ConversationID) async {
        var members: [ConversationMember] = []
        // The least fresh page's summary: the snapshot as a whole is only as current as that.
        var summary: ConversationRosterSummary?
        var pagingToken: Data?
        var pages = 0
        var isComplete = false

        do {
            while pages < pageCap {
                let page = try await fetching.getRosterPage(owner: owner, conversationID: conversationID, pagingToken: pagingToken)
                pages += 1
                members.append(contentsOf: page.members)
                if page.rosterSummary.version < summary?.version ?? .max {
                    summary = page.rosterSummary
                }
                guard let next = page.nextPagingToken else {
                    isComplete = true
                    break
                }
                pagingToken = next
            }
            guard let summary else { return }
            try database.mergeRosterSnapshot(members, summary: summary, isComplete: isComplete, conversationID: conversationID)
            logger.info("Synced roster", metadata: [
                "conversationID": "\(conversationID)",
                "members": "\(members.count)",
                "pages": "\(pages)",
                "isComplete": "\(isComplete)",
            ])
        } catch {
            await report(error, reason: "Failed to sync roster", conversationID: conversationID)
        }
    }

    private func report(_ error: Error, reason: String, conversationID: ConversationID) async {
        logger.error("Roster sync failed", metadata: [
            "reason": "\(reason)",
            "conversationID": "\(conversationID)",
            "error": "\(error)",
        ])
        await ErrorReporting.captureError(error, reason: reason)
    }
}
